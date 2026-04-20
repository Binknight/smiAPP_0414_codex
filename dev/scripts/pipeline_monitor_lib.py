from __future__ import annotations

import logging
import threading
import time
from pathlib import Path
from typing import Any

from common import (
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


def prepare_logger(repo_root: Path, config: dict[str, Any], suffix: str) -> logging.Logger:
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
    logger: logging.Logger,
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


def initialize_inspection(state: dict[str, Any]) -> dict[str, Any]:
    inspection = state.get("inspection") or {}
    inspection.setdefault("status", "pending")
    inspection.setdefault("last_checked_at", None)
    inspection.setdefault("cycle_count", 0)
    inspection.setdefault("message", "等待巡检")
    state["inspection"] = inspection
    return state


def update_inspection_state(
    state: dict[str, Any],
    *,
    status: str,
    message: str,
) -> dict[str, Any]:
    inspection = state.get("inspection") or {}
    inspection["status"] = status
    inspection["last_checked_at"] = now_local_iso()
    inspection["cycle_count"] = int(inspection.get("cycle_count") or 0) + 1
    inspection["message"] = message
    state["inspection"] = inspection
    state["updated_at"] = now_local_iso()
    return state


def persist_state(
    state_file: Path,
    state: dict[str, Any],
    logger: logging.Logger,
) -> None:
    latest = load_runtime_state(state_file)
    if latest and latest.get("web") and not state.get("web"):
        state["web"] = latest["web"]
    if latest and latest.get("result_payload") and not state.get("result_payload"):
        state["result_payload"] = latest["result_payload"]
    if latest and latest.get("status") == "cancelled" and state.get("status") != "cancelled":
        state["status"] = "cancelled"
        state["cancelled_at"] = latest.get("cancelled_at")
        state["cancel_reason"] = latest.get("cancel_reason")
        state["inspection"] = latest.get("inspection", state.get("inspection"))
        state["updated_at"] = latest.get("updated_at", now_local_iso())
    update_runtime_state(state_file, state, logger)


def handle_state_file(
    repo_root: Path,
    config: dict[str, Any],
    state_file: Path,
    logger: logging.Logger,
    dry_run: bool,
) -> None:
    state = load_runtime_state(state_file)
    if not state:
        logger.warning("状态文件不存在或为空: %s", state_file)
        return

    state = initialize_inspection(state)
    result_json = Path(state["result_json"])
    pid = state.get("agent", {}).get("pid")
    logger.info("开始巡检场景: %s", state.get("scenario_branch"))

    if state.get("status") == "cancelled":
        update_inspection_state(state, status="cancelled", message="任务已取消，停止巡检")
        persist_state(state_file, state, logger)
        return

    if state.get("status") == "dry_run":
        update_inspection_state(state, status="done", message="dry-run 模式，未实际启动 Agent")
        persist_state(state_file, state, logger)
        return

    if result_json.exists():
        result_payload = read_json(result_json)
        success = detect_build_success(result_payload, config["scheduler"]["success_values"])
        state["result_payload"] = result_payload
        if success:
            if state.get("status") == "pushed":
                update_inspection_state(state, status="done", message="结果已成功推送")
                persist_state(state_file, state, logger)
                return
            logger.info("检测到成功结果 JSON，开始提交并推送。")
            update_inspection_state(state, status="running", message="检测到成功结果，准备提交推送")
            persist_state(state_file, state, logger)
            commit_and_push(repo_root, config, state, logger, dry_run)
            state["status"] = "pushed" if not dry_run else "dry_run_success_detected"
            state["pushed_at"] = now_local_iso()
            update_inspection_state(
                state,
                status="done",
                message="结果已处理完成" if not dry_run else "dry-run 检测到成功结果",
            )
            persist_state(state_file, state, logger)
            return

        logger.warning("结果 JSON 已生成，但 build 状态不是成功。")
        state["status"] = "build_failed"
        update_inspection_state(state, status="failed", message="结果已生成，但构建失败")
        persist_state(state_file, state, logger)
        return

    if is_process_running(pid):
        state["status"] = "inspection_running"
        update_inspection_state(state, status="running", message="Agent 运行中，等待结果文件")
        persist_state(state_file, state, logger)
        return

    logger.warning("Agent 进程已结束，但仍未检测到结果 JSON。")
    state["status"] = "agent_exited_without_result"
    update_inspection_state(state, status="failed", message="Agent 已退出，但未产出结果")
    persist_state(state_file, state, logger)


def run_loop(
    repo_root: Path,
    config: dict[str, Any],
    state_arg: str | None,
    logger: logging.Logger,
    dry_run: bool,
    stop_event: threading.Event | None = None,
) -> None:
    interval = int(config["scheduler"]["poll_interval_seconds"])
    max_cycles = int(config["scheduler"]["max_cycles"])
    logger.info("开始循环巡检，间隔 %s 秒，最多 %s 轮。", interval, max_cycles)
    for index in range(max_cycles):
        if stop_event and stop_event.is_set():
            logger.info("巡检收到停止信号，结束轮询。")
            return
        logger.info("巡检轮次: %s/%s", index + 1, max_cycles)
        state_files = collect_state_files(repo_root, config, state_arg)
        if not state_files:
            logger.info("当前轮次未发现状态文件。")
        for state_file in state_files:
            if stop_event and stop_event.is_set():
                logger.info("巡检收到停止信号，结束当前轮询。")
                return
            handle_state_file(repo_root, config, state_file, logger, dry_run)
        if index < max_cycles - 1:
            time.sleep(interval)
