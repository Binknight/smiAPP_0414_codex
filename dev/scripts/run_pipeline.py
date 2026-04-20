from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

from common import (
    configure_stdio,
    detect_build_success,
    ensure_dir,
    ensure_remote,
    format_command,
    git_has_local_changes,
    infer_scenario_id,
    is_process_running,
    load_runtime_state,
    normalize_app_key,
    now_local_iso,
    read_json,
    read_text,
    render_template,
    resolve_path,
    run_command,
    sanitize_name,
    setup_logger,
    update_runtime_state,
    utc_now_compact,
    write_json,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="APP 特定场景自动化编排脚本")
    parser.add_argument("--config", default="dev/config/pipeline.config.json", help="主配置文件路径")
    parser.add_argument("--input", dest="input_json", default=None, help="场景 JSON 路径")
    parser.add_argument("--scenario-id", default=None, help="手动指定场景编号")
    parser.add_argument("--wait", action="store_true", help="下发 Agent 后等待进程结束")
    parser.add_argument("--resume", action="store_true", help="存在运行状态时尝试恢复")
    parser.add_argument("--force-retry", action="store_true", help="忽略已有失败状态，重新下发 Agent")
    parser.add_argument("--dry-run", action="store_true", help="仅打印计划，不实际执行 git 和 agent 命令")
    return parser.parse_args()


def load_config(config_path: Path) -> dict[str, Any]:
    return read_json(config_path)


def prepare_logger(repo_root: Path, config: dict[str, Any], scenario_name: str) -> tuple[Any, Path]:
    logs_root = resolve_path(repo_root, config["paths"]["logs_root"])
    ensure_dir(logs_root)
    log_file = logs_root / f"pipeline-{sanitize_name(scenario_name)}-{utc_now_compact()}.log"
    logger = setup_logger("dev-pipeline", log_file)
    return logger, log_file


def build_runtime_paths(repo_root: Path, config: dict[str, Any], scenario_key: str) -> dict[str, Path]:
    result_root = ensure_dir(resolve_path(repo_root, config["paths"]["result_root"]))
    state_root = ensure_dir(resolve_path(repo_root, config["paths"]["state_root"]))
    mock_root = ensure_dir(resolve_path(repo_root, config["paths"]["mock_data_root"]))
    return {
        "result_json": result_root / f"{scenario_key}.result.json",
        "state_file": state_root / f"{scenario_key}.runtime.json",
        "mock_dir": mock_root / scenario_key,
    }


def ensure_base_branch(
    repo_root: Path,
    config: dict[str, Any],
    base_branch: str,
    logger: Any,
    dry_run: bool,
) -> None:
    git_config = config["git"]
    remote_name = git_config["remote_name"]
    app_types = git_config["app_types"]

    ensure_remote(repo_root, git_config, logger)
    if dry_run:
        logger.info("当前为 dry-run，跳过远端抓取和分支切换。")
        return

    if git_has_local_changes(repo_root):
        logger.warning("当前工作区存在未提交改动。若影响分支切换，请先提交或暂存后再执行。")

    if git_config.get("fetch_all_known_branches", False):
        branches = sorted({app_info["base_branch"] for app_info in app_types.values()})
        run_command(["git", "fetch", "--prune", remote_name, *branches], repo_root, logger)
    else:
        run_command(["git", "fetch", "--prune", remote_name, base_branch], repo_root, logger)

    run_command(["git", "checkout", base_branch], repo_root, logger)
    run_command(["git", "pull", "--ff-only", remote_name, base_branch], repo_root, logger)


def ensure_scenario_branch(
    repo_root: Path,
    scenario_branch: str,
    logger: Any,
    dry_run: bool,
) -> None:
    if dry_run:
        logger.info("当前为 dry-run，跳过场景分支创建。目标分支: %s", scenario_branch)
        return

    exists = subprocess.run(
        ["git", "rev-parse", "--verify", scenario_branch],
        cwd=str(repo_root),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if exists.returncode == 0:
        logger.info("场景分支已存在，直接切换: %s", scenario_branch)
        run_command(["git", "checkout", scenario_branch], repo_root, logger)
        return

    run_command(["git", "checkout", "-b", scenario_branch], repo_root, logger)


def build_prompt_variables(
    input_path: Path,
    scenario_payload: dict[str, Any],
    app_key: str,
    app_info: dict[str, Any],
    base_branch: str,
    scenario_branch: str,
    mock_dir: Path,
    result_json: Path,
    build_command: str,
) -> dict[str, str]:
    return {
        "INPUT_JSON_PATH": str(input_path),
        "INPUT_JSON_CONTENT": json_dumps(scenario_payload),
        "APP_TYPE": app_key,
        "APP_DISPLAY_NAME": str(app_info.get("display_name", app_key)),
        "BASE_BRANCH": base_branch,
        "SCENARIO_BRANCH": scenario_branch,
        "MOCK_DATA_DIR": str(mock_dir),
        "RESULT_JSON_PATH": str(result_json),
        "BUILD_COMMAND": build_command,
    }


def json_dumps(payload: dict[str, Any]) -> str:
    import json

    return json.dumps(payload, ensure_ascii=False, indent=2)


def build_powershell_here_string(content: str) -> str:
    lines = content.splitlines()
    if content.endswith(("\n", "\r")):
        lines.append("")

    chunks: list[str] = []
    current: list[str] = []
    quote_mode = "single"

    def flush_current() -> None:
        if not current:
            return
        if quote_mode == "single":
            chunks.append("@'\n" + "\n".join(current) + "\n'@")
        else:
            chunks.append('@\"\n' + "\n".join(current) + '\n\"@')
        current.clear()

    for line in lines:
        if line == "'@":
            flush_current()
            chunks.append('"\'@"')
            quote_mode = "double"
            continue
        if line == '"@':
            flush_current()
            chunks.append("'\"@'")
            quote_mode = "single"
            continue
        current.append(line)

    flush_current()
    if not chunks:
        return "@'\n'@"
    return " + [Environment]::NewLine + ".join(chunks)


def wrap_codex_command_with_powershell(command: list[str]) -> list[str]:
    if len(command) < 4 or command[:3] != ["codex.cmd", "exec", "--yolo"]:
        return command

    task_prompt = command[3]
    if "\n" not in task_prompt and "\r" not in task_prompt:
        return command

    prompt_literal = build_powershell_here_string(task_prompt)
    script = (
        f"$taskPrompt = {prompt_literal}; "
        "& codex.cmd exec --yolo $taskPrompt"
    )
    return ["powershell", "-NoProfile", "-Command", script]


def summarize_agent_command(command: list[str]) -> str:
    if len(command) >= 4 and command[:3] == ["powershell", "-NoProfile", "-Command"]:
        script = command[3]
        if script.startswith("$taskPrompt = ") and "& codex.cmd exec --yolo $taskPrompt" in script:
            return "powershell -NoProfile -Command <here-string taskPrompt> -> codex.cmd exec --yolo $taskPrompt"
    return format_command(command)


def instantiate_agent_command(
    agent_definition: dict[str, Any],
    task_prompt: str,
) -> tuple[list[str], dict[str, str]]:
    variables = {"TASK_PROMPT": task_prompt}
    command = [render_template(str(part), variables) for part in agent_definition["command"]]
    command = wrap_codex_command_with_powershell(command)
    env = {
        key: render_template(str(value), variables)
        for key, value in agent_definition.get("env", {}).items()
    }
    return command, env


def dispatch_agent(
    repo_root: Path,
    state: dict[str, Any],
    agent_command: list[str],
    extra_env: dict[str, str],
    logger: Any,
    dry_run: bool,
) -> dict[str, Any]:
    logger.info("即将下发 Agent 任务: %s", summarize_agent_command(agent_command))
    if dry_run:
        state["status"] = "dry_run"
        state["agent"] = {
            **state["agent"],
            "command": agent_command,
            "pid": None,
            "started_at": None,
        }
        return state

    agent_log_path = Path(state["agent"]["log_path"])
    ensure_dir(agent_log_path.parent)
    handle = agent_log_path.open("a", encoding="utf-8")
    env = os.environ.copy()
    env.update(extra_env)
    process = subprocess.Popen(
        agent_command,
        cwd=str(repo_root),
        stdout=handle,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=env,
    )
    handle.close()

    state["status"] = "agent_running"
    state["agent"] = {
        **state["agent"],
        "command": agent_command,
        "pid": process.pid,
        "started_at": now_local_iso(),
    }
    logger.info("Agent 已启动，PID=%s，日志=%s", process.pid, agent_log_path)
    return state


def main() -> int:
    configure_stdio()
    args = parse_args()
    config_path = Path(args.config).resolve()
    config = load_config(config_path)
    repo_root = resolve_path(config_path.parent.parent.parent, config["paths"]["repo_root"])

    input_json = args.input_json or config["paths"]["default_input_json"]
    input_path = resolve_path(repo_root, input_json)
    if not input_path.exists():
        raise FileNotFoundError(f"场景 JSON 不存在: {input_path}")

    scenario_payload = read_json(input_path)
    raw_app = scenario_payload.get("app")
    app_key, app_info = normalize_app_key(config, raw_app)
    scenario_id = args.scenario_id or infer_scenario_id(input_path, int(config["git"].get("scenario_id_padding", 3)))
    scenario_branch = config["git"]["scenario_branch_format"].format(
        app_segment=app_info["app_segment"],
        scenario_id=scenario_id,
    )
    scenario_key = sanitize_name(f"{app_key}-{scenario_id}")

    logger, log_file = prepare_logger(repo_root, config, scenario_key)
    logger.info("开始执行 APP 场景自动化编排")
    logger.info("场景输入: %s", input_path)
    logger.info("识别 APP 类型: %s (%s)", app_key, app_info.get("display_name", app_key))
    logger.info("目标场景分支: %s", scenario_branch)

    runtime_paths = build_runtime_paths(repo_root, config, scenario_key)
    ensure_dir(runtime_paths["mock_dir"])
    state_file = runtime_paths["state_file"]
    existing_state = load_runtime_state(state_file)
    if existing_state and not args.force_retry:
        pid = existing_state.get("agent", {}).get("pid")
        if is_process_running(pid):
            logger.info("检测到已有运行中的 Agent 任务，PID=%s。", pid)
            if args.resume or args.wait:
                logger.info("复用已有运行状态，不重复下发。")
                if args.wait:
                    logger.info("当前仅保留状态，建议配合 monitor_results.py 进行巡检。")
                return 0
            logger.info("如需重试请使用 --force-retry。")
            return 0

        if existing_state.get("status") == "completed":
            logger.info("该场景已完成，结果文件: %s", existing_state.get("result_json"))
            return 0

        logger.warning("检测到历史状态但 Agent 已不在运行。将状态视为可恢复/可重试。")

    base_branch = app_info["base_branch"]
    template_path = resolve_path(repo_root, config["paths"]["task_template"])
    template_text = read_text(template_path)
    build_command = config["build"]["command"]
    prompt_variables = build_prompt_variables(
        input_path=input_path,
        scenario_payload=scenario_payload,
        app_key=app_key,
        app_info=app_info,
        base_branch=base_branch,
        scenario_branch=scenario_branch,
        mock_dir=runtime_paths["mock_dir"],
        result_json=runtime_paths["result_json"],
        build_command=build_command,
    )
    task_prompt = render_template(template_text, prompt_variables)

    state = {
        "scenario_id": scenario_id,
        "scenario_key": scenario_key,
        "scenario_input": str(input_path),
        "app_type": app_key,
        "app_display_name": app_info.get("display_name", app_key),
        "base_branch": base_branch,
        "scenario_branch": scenario_branch,
        "status": "initialized",
        "created_at": now_local_iso(),
        "updated_at": now_local_iso(),
        "log_file": str(log_file),
        "mock_data_dir": str(runtime_paths["mock_dir"]),
        "result_json": str(runtime_paths["result_json"]),
        "agent": {
            "type": config["agent"]["active"],
            "log_path": str(resolve_path(repo_root, config["paths"]["logs_root"]) / f"agent-{scenario_key}-{utc_now_compact()}.log"),
            "command": [],
            "pid": None,
            "started_at": None,
        },
    }
    update_runtime_state(state_file, state, logger)

    logger.info("准备进行 Git 基础分支同步。")
    ensure_base_branch(repo_root, config, base_branch, logger, args.dry_run)
    logger.info("准备创建/切换场景分支。")
    ensure_scenario_branch(repo_root, scenario_branch, logger, args.dry_run)

    agent_definition = config["agent"]["definitions"][config["agent"]["active"]]
    agent_command, extra_env = instantiate_agent_command(agent_definition, task_prompt)
    state = dispatch_agent(repo_root, state, agent_command, extra_env, logger, args.dry_run)
    state["updated_at"] = now_local_iso()
    update_runtime_state(state_file, state, logger)

    if args.wait and not args.dry_run:
        pid = state["agent"]["pid"]
        logger.info("已启用 --wait，将等待 Agent 进程结束。PID=%s", pid)
        try:
            process = subprocess.Popen(
                ["powershell", "-Command", f"Wait-Process -Id {pid}"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            process.wait()
        except KeyboardInterrupt:
            logger.warning("收到中断信号，保留状态文件供后续恢复。")
            return 130

        if Path(state["result_json"]).exists():
            result_payload = read_json(Path(state["result_json"]))
            success = detect_build_success(result_payload, config["scheduler"]["success_values"])
            state["status"] = "completed" if success else "agent_finished_waiting_review"
        else:
            state["status"] = "agent_exited_without_result"
        state["updated_at"] = now_local_iso()
        update_runtime_state(state_file, state, logger)

    logger.info("自动化下发完成。后续可执行 monitor_results.py 进行结果巡检与推送。")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"执行失败: {exc}", file=sys.stderr)
        sys.exit(1)
