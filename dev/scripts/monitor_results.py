from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path
from typing import Any

from common import (
    configure_stdio,
    detect_build_success,
    ensure_dir,
    is_process_running,
    load_runtime_state,
    now_local_iso,
    read_json,
    resolve_path,
    run_command,
    sanitize_name,
    setup_logger,
    update_runtime_state,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="巡检 APP 场景结果并自动提交推送")
    parser.add_argument("--config", default="dev/config/pipeline.config.json", help="主配置文件路径")
    parser.add_argument("--once", action="store_true", help="只巡检一次")
    parser.add_argument("--loop", action="store_true", help="按配置持续轮询")
    parser.add_argument("--state", default=None, help="只处理指定的运行状态文件")
    parser.add_argument("--dry-run", action="store_true", help="仅打印动作，不实际 commit/push")
    return parser.parse_args()


def load_config(config_path: Path) -> dict[str, Any]:
    return read_json(config_path)


def prepare_logger(repo_root: Path, config: dict[str, Any], suffix: str) -> Any:
    logs_root = ensure_dir(resolve_path(repo_root, config["paths"]["logs_root"]))
    log_file = logs_root / f"monitor-{sanitize_name(suffix)}.log"
    return setup_logger("dev-monitor", log_file)


def collect_state_files(repo_root: Path, config: dict[str, Any], state_arg: str | None) -> list[Path]:
    if state_arg:
        return [resolve_path(repo_root, state_arg)]
    state_root = ensure_dir(resolve_path(repo_root, config["paths"]["state_root"]))
    return sorted(state_root.glob("*.runtime.json"))


def commit_and_push(
    repo_root: Path,
    config: dict[str, Any],
    state: dict[str, Any],
    logger: Any,
    dry_run: bool,
) -> None:
    commit_config = config["commit"]
    scheduler_config = config["scheduler"]
    remote_name = config["git"]["remote_name"]
    include_paths = list(commit_config["include_paths"])
    scenario_branch = state["scenario_branch"]
    commit_message = scheduler_config["commit_message_template"].format(
        scenario_branch=scenario_branch,
        scenario_id=state["scenario_id"],
        app_type=state["app_type"],
    )
    scenario_input = Path(state["scenario_input"])
    try:
        include_paths.append(str(scenario_input.relative_to(repo_root)))
    except ValueError:
        logger.warning("场景输入文件不在仓库内，跳过自动纳入提交白名单: %s", scenario_input)
    include_paths = list(dict.fromkeys(include_paths))

    logger.info("准备提交以下路径白名单中的改动: %s", ", ".join(include_paths))
    if dry_run:
        logger.info("dry-run 模式，不实际执行 git add/commit/push。")
        return

    run_command(["git", "checkout", scenario_branch], repo_root, logger)
    run_command(["git", "add", "--", *include_paths], repo_root, logger)

    status_result = run_command(["git", "status", "--short"], repo_root, logger, check=False)
    if not status_result.stdout.strip():
        logger.info("当前没有可提交的改动，跳过 commit。")
    else:
        run_command(["git", "commit", "-m", commit_message], repo_root, logger)

    run_command(["git", "push", "-u", remote_name, scenario_branch], repo_root, logger)


def handle_state_file(
    repo_root: Path,
    config: dict[str, Any],
    state_file: Path,
    logger: Any,
    dry_run: bool,
) -> None:
    state = load_runtime_state(state_file)
    if not state:
        logger.warning("状态文件不存在或为空: %s", state_file)
        return

    state["updated_at"] = now_local_iso()
    result_json = Path(state["result_json"])
    pid = state.get("agent", {}).get("pid")
    logger.info("开始巡检场景: %s", state.get("scenario_branch"))

    if result_json.exists():
        result_payload = read_json(result_json)
        success = detect_build_success(result_payload, config["scheduler"]["success_values"])
        state["result_payload"] = result_payload
        if success:
            if state.get("status") == "pushed":
                logger.info("该场景已成功推送，跳过重复处理。")
                update_runtime_state(state_file, state, logger)
                return
            logger.info("检测到成功结果 JSON，开始提交并推送。")
            commit_and_push(repo_root, config, state, logger, dry_run)
            state["status"] = "pushed" if not dry_run else "dry_run_success_detected"
            state["pushed_at"] = now_local_iso()
            update_runtime_state(state_file, state, logger)
            return

        logger.warning("结果 JSON 已生成，但 build 状态不是成功。")
        state["status"] = "build_failed"
        update_runtime_state(state_file, state, logger)
        return

    if is_process_running(pid):
        logger.info("结果 JSON 尚未生成，Agent 进程仍在运行。PID=%s", pid)
        state["status"] = "agent_running"
        update_runtime_state(state_file, state, logger)
        return

    logger.warning("Agent 进程已结束，但仍未检测到结果 JSON。")
    state["status"] = "agent_exited_without_result"
    update_runtime_state(state_file, state, logger)


def main() -> int:
    configure_stdio()
    args = parse_args()
    config_path = Path(args.config).resolve()
    config = load_config(config_path)
    repo_root = resolve_path(config_path.parent.parent.parent, config["paths"]["repo_root"])
    logger = prepare_logger(repo_root, config, "loop" if args.loop else "once")

    state_files = collect_state_files(repo_root, config, args.state)
    if not state_files:
        logger.info("没有检测到待巡检的状态文件。")
        return 0

    if args.loop:
        interval = int(config["scheduler"]["poll_interval_seconds"])
        max_cycles = int(config["scheduler"]["max_cycles"])
        logger.info("开始循环巡检，间隔 %s 秒，最多 %s 轮。", interval, max_cycles)
        for index in range(max_cycles):
            logger.info("巡检轮次: %s/%s", index + 1, max_cycles)
            state_files = collect_state_files(repo_root, config, args.state)
            if not state_files:
                logger.info("当前轮次未发现状态文件。")
            for state_file in state_files:
                handle_state_file(repo_root, config, state_file, logger, args.dry_run)
            time.sleep(interval)
        return 0

    for state_file in state_files:
        handle_state_file(repo_root, config, state_file, logger, args.dry_run)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"执行失败: {exc}", file=sys.stderr)
        sys.exit(1)
