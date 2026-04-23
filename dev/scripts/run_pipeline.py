from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
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
    windows_subprocess_kwargs,
)
from pipeline_monitor_lib import initialize_inspection


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="APP 特定场景自动化编排脚本")
    parser.add_argument("--config", default="dev/config/pipeline.config.json", help="主配置文件路径")
    parser.add_argument("--input", dest="input_json", default=None, help="场景 JSON 路径")
    parser.add_argument("--scenario-id", default=None, help="手动指定场景编号")
    parser.add_argument("--wait", action="store_true", help="下发 Agent 后等待进程结束")
    parser.add_argument("--resume", action="store_true", help="存在运行状态时尝试恢复")
    parser.add_argument("--force-retry", action="store_true", help="忽略已有失败状态，重新下发 Agent")
    parser.add_argument("--dry-run", action="store_true", help="仅打印计划，不实际执行 git 和 agent 命令")
    parser.add_argument("--no-web", action="store_true", help="不自动启动 Web 控制台")
    return parser.parse_args()


def load_config(config_path: Path) -> dict[str, Any]:
    return read_json(config_path)


def normalize_scenario_dir_name(raw_scenario_id: str) -> str:
    text = sanitize_name(raw_scenario_id)
    if not text:
        raise ValueError("场景编号不能为空")
    if text.startswith("scenario"):
        return text
    return f"scenario{text}"


def get_repo_root(config_path: Path, config: dict[str, Any]) -> Path:
    return resolve_path(config_path.parent.parent.parent, config["paths"]["repo_root"])


def get_base_app_root(repo_root: Path, config: dict[str, Any]) -> Path:
    return resolve_path(repo_root, config["paths"]["base_app_root"])


def get_scenarios_root(repo_root: Path, config: dict[str, Any]) -> Path:
    return ensure_dir(resolve_path(repo_root, config["paths"]["scenarios_root"]))


def prepare_scenario_root(
    repo_root: Path,
    config: dict[str, Any],
    scenario_dir_name: str,
    logger: Any,
    dry_run: bool,
) -> Path:
    base_app_root = get_base_app_root(repo_root, config)
    scenarios_root = get_scenarios_root(repo_root, config)
    scenario_root = scenarios_root / scenario_dir_name

    if scenario_root.exists() and (scenario_root / "entry").exists():
        logger.info("复用现有场景目录: %s", scenario_root)
        return scenario_root

    if dry_run:
        logger.info("dry-run 模式，跳过初始化场景目录: %s", scenario_root)
        return scenario_root

    if scenario_root.exists():
        for item in scenario_root.iterdir():
            if item.name == "logs":
                continue
            try:
                if item.is_dir():
                    shutil.rmtree(item)
                else:
                    item.unlink()
            except Exception as exc:
                logger.warning("清理场景目录时跳过无法删除的项: %s (%s)", item, exc)
    shutil.copytree(
        base_app_root,
        scenario_root,
        ignore=shutil.ignore_patterns("build", ".hvigor", "mock-data", "output", "logs", "state", "spec"),
        dirs_exist_ok=True,
    )
    logger.info("已基于 baseApp 初始化场景目录: %s", scenario_root)
    return scenario_root


def build_runtime_paths(scenario_root: Path) -> dict[str, Path]:
    spec_dir = ensure_dir(scenario_root / "spec")
    mock_dir = ensure_dir(scenario_root / "mock-data")
    output_dir = ensure_dir(scenario_root / "output")
    logs_dir = ensure_dir(scenario_root / "logs")
    state_dir = ensure_dir(scenario_root / "state")
    return {
        "spec_dir": spec_dir,
        "mock_dir": mock_dir,
        "output_dir": output_dir,
        "logs_dir": logs_dir,
        "state_dir": state_dir,
        "result_json": output_dir / "result.json",
        "state_file": state_dir / "runtime.json",
    }


def prepare_logger(runtime_paths: dict[str, Path], scenario_name: str) -> tuple[Any, Path]:
    log_file = runtime_paths["logs_dir"] / f"pipeline-{sanitize_name(scenario_name)}-{utc_now_compact()}.log"
    logger = setup_logger("dev-pipeline", log_file)
    return logger, log_file


def update_state_status(state: dict[str, Any], status: str) -> dict[str, Any]:
    state["status"] = status
    state["updated_at"] = now_local_iso()
    return state


def write_task_prompt_snapshot(runtime_paths: dict[str, Path], task_prompt: str) -> Path:
    prompt_path = runtime_paths["spec_dir"] / "task_prompt.txt"
    prompt_path.write_text(task_prompt, encoding="utf-8")
    return prompt_path


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
        logger.warning("当前工作区存在未提交改动。若影响分支切换，请先处理后重试。")

    if git_config.get("fetch_all_known_branches", False):
        branches = sorted({app_info["base_branch"] for app_info in app_types.values()})
        run_command(["git", "fetch", "--prune", remote_name, *branches], repo_root, logger)
    else:
        run_command(["git", "fetch", "--prune", remote_name, base_branch], repo_root, logger)

    run_command(["git", "checkout", base_branch], repo_root, logger)
    run_command(["git", "pull", "--ff-only", remote_name, base_branch], repo_root, logger)


def build_prompt_variables(
    input_path: Path,
    scenario_payload: dict[str, Any],
    app_key: str,
    app_info: dict[str, Any],
    branch_name: str,
    scenario_dir_name: str,
    scenario_root: Path,
    runtime_paths: dict[str, Path],
    build_command: str,
    build_target: str,
) -> dict[str, str]:
    task_prompt_file = (runtime_paths["spec_dir"] / "task_prompt.txt").resolve()
    opencode_model = os.environ.get("OPENCODE_MODEL", "mlops/qwen35-35b-vl")
    return {
        "INPUT_JSON_PATH": str(input_path),
        "INPUT_JSON_CONTENT": json.dumps(scenario_payload, ensure_ascii=False, indent=2),
        "APP_TYPE": app_key,
        "APP_DISPLAY_NAME": str(app_info.get("display_name", app_key)),
        "BASE_BRANCH": branch_name,
        "BRANCH_NAME": branch_name,
        "SCENARIO_NAME": scenario_dir_name,
        "SCENARIO_ROOT": str(scenario_root),
        "SPEC_DIR": str(runtime_paths["spec_dir"]),
        "MOCK_DATA_DIR": str(runtime_paths["mock_dir"]),
        "RESULT_JSON_PATH": str(runtime_paths["result_json"]),
        "BUILD_TARGET": build_target,
        "BUILD_COMMAND": f"{build_command} -Target {build_target}",
        "TASK_PROMPT_FILE": str(task_prompt_file),
        "OPENCODE_MODEL": opencode_model,
    }


def _truncate_log_command(command: list[str], last_arg_max: int = 200) -> str:
    if not command:
        return ""
    if len(command[-1]) > last_arg_max:
        last = f"{command[-1][:last_arg_max]}...（共 {len(command[-1])} 字）"
        return format_command([*command[:-1], last])
    return format_command(command)


def summarize_agent_command(command: list[str], task_via_stdin: bool) -> str:
    if task_via_stdin and len(command) >= 4 and command[:4] == ["codex.cmd", "exec", "--yolo", "-"]:
        return "codex.cmd exec --yolo - < stdin(taskPrompt)"
    if not task_via_stdin:
        return f"（任务在 argv 中，不写入 stdin）\n{_truncate_log_command(command)}"
    return _truncate_log_command(command)


def build_agent_runtime_info(repo_root: Path, config: dict[str, Any]) -> dict[str, Any]:
    agent_key = config["agent"]["active"]
    agent_definition = config["agent"]["definitions"].get(agent_key, {})
    name = str(agent_definition.get("display_name", agent_key)).replace("_", " ").lower()
    base = {"workspace": str(repo_root), "name": name}
    family = (agent_definition.get("runtime_family") or "").lower()
    if family == "opencode":
        return {
            **base,
            "model": os.environ.get("OPENCODE_MODEL", "mlops/qwen35-35b-vl"),
            "provider": os.environ.get("OPENCODE_PROVIDER", "（models.dev / 已登录提供商）"),
            "approval_policy": os.environ.get("OPENCODE_PERMISSION", "见 OPENCODE_PERMISSION"),
            "sandbox_mode": "opencode 内置工具权限",
            "reasoning_effort": os.environ.get("OPENCODE_REASONING_EFFORT", "—"),
            "reasoning_summary": os.environ.get("OPENCODE_REASONING_SUMMARY", "—"),
            "session_id": os.environ.get("OPENCODE_SESSION_ID"),
        }
    return {
        **base,
        "model": os.environ.get("CODEX_MODEL", "gpt-5.4"),
        "provider": os.environ.get("CODEX_PROVIDER", "openai"),
        "approval_policy": os.environ.get("CODEX_APPROVAL_POLICY", "never"),
        "sandbox_mode": os.environ.get("CODEX_SANDBOX_MODE", "danger-full-access"),
        "reasoning_effort": os.environ.get("CODEX_REASONING_EFFORT", "medium"),
        "reasoning_summary": os.environ.get("CODEX_REASONING_SUMMARY", "none"),
        "session_id": os.environ.get("CODEX_SESSION_ID") or os.environ.get("OPENAI_SESSION_ID"),
    }


def instantiate_agent_command(
    agent_definition: dict[str, Any],
    task_prompt: str,
    extra_template: dict[str, str] | None = None,
) -> tuple[list[str], dict[str, str]]:
    variables: dict[str, str] = {"TASK_PROMPT": task_prompt}
    if extra_template:
        variables.update(extra_template)
    command = [render_template(str(part), variables) for part in agent_definition["command"]]
    env = {
        key: render_template(str(value), variables)
        for key, value in agent_definition.get("env", {}).items()
    }
    return command, env


def dispatch_agent(
    repo_root: Path,
    state: dict[str, Any],
    agent_command: list[str],
    task_prompt: str,
    extra_env: dict[str, str],
    logger: Any,
    dry_run: bool,
    task_via_stdin: bool = True,
) -> dict[str, Any]:
    logger.info("即将下发 Agent 任务: %s", summarize_agent_command(agent_command, task_via_stdin=task_via_stdin))
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
    stdin = subprocess.PIPE if task_via_stdin else subprocess.DEVNULL
    process = subprocess.Popen(
        agent_command,
        cwd=str(repo_root),
        stdout=handle,
        stderr=subprocess.STDOUT,
        stdin=stdin,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=env,
    )
    if task_via_stdin and process.stdin is not None:
        process.stdin.write(task_prompt)
        process.stdin.close()
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


def wait_log_web_url(state_file: Path, logger: Any, max_wait_sec: float = 5.0) -> str | None:
    """等待 dev-web 在状态文件中写入 web.url（子进程在绑定端口后才会更新）。"""
    deadline = time.time() + max_wait_sec
    while time.time() < deadline:
        time.sleep(0.2)
        state = load_runtime_state(state_file)
        if not state:
            continue
        url = (state.get("web") or {}).get("url")
        if url:
            return str(url)
    return None


def start_web_console(
    repo_root: Path,
    config_path: Path,
    pipeline_key: str,
    logger: Any,
    dry_run: bool,
) -> None:
    scenario_logs = ensure_dir(repo_root / "scenarios" / pipeline_key / "logs")
    web_log = scenario_logs / "web-console.log"
    command = [
        sys.executable,
        str((repo_root / "dev" / "scripts" / "web_console.py").resolve()),
        "--config",
        str(config_path),
        "--selected",
        pipeline_key,
        "--host",
        "127.0.0.1",
        "--port",
        "8765",
        "--log-file",
        str(web_log),
    ]
    if dry_run:
        command.append("--dry-run")

    creationflags = 0
    if os.name == "nt":
        creationflags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS
    subprocess.Popen(
        command,
        cwd=str(repo_root),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        text=True,
        encoding="utf-8",
        errors="replace",
        creationflags=creationflags,
        close_fds=True,
    )
    logger.info("Web 控制台启动命令已下发，默认选中: %s，日志: %s", pipeline_key, web_log)


def wait_for_agent_result(
    state: dict[str, Any],
    state_file: Path,
    config: dict[str, Any],
    logger: Any,
) -> dict[str, Any]:
    pid = state["agent"]["pid"]
    logger.info("已启用 --wait，将等待 Agent 进程结束。PID=%s", pid)
    try:
        process = subprocess.Popen(
            ["powershell", "-Command", f"Wait-Process -Id {pid}"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            **windows_subprocess_kwargs(),
        )
        process.wait()
    except KeyboardInterrupt:
        logger.warning("收到中断信号，保留状态文件供后续恢复。")
        raise

    result_json = Path(state["result_json"])
    if result_json.exists():
        result_payload = read_json(result_json)
        success = detect_build_success(result_payload, config["scheduler"]["success_values"])
        state["status"] = "completed" if success else "agent_finished_waiting_review"
        state["runtime_ended_at"] = now_local_iso()
    else:
        state["status"] = "agent_exited_without_result"
        state["runtime_ended_at"] = now_local_iso()
    state["updated_at"] = now_local_iso()
    update_runtime_state(state_file, state, logger)
    return state


def main() -> int:
    configure_stdio()
    args = parse_args()
    config_path = Path(args.config).resolve()
    config = load_config(config_path)
    repo_root = get_repo_root(config_path, config)

    input_json = args.input_json or config["paths"]["default_input_json"]
    input_path = resolve_path(repo_root, input_json)
    if not input_path.exists():
        raise FileNotFoundError(f"场景 JSON 不存在: {input_path}")

    scenario_payload = read_json(input_path)
    raw_app = scenario_payload.get("app")
    app_key, app_info = normalize_app_key(config, raw_app)
    scenario_id = args.scenario_id or infer_scenario_id(input_path, int(config["git"].get("scenario_id_padding", 3)))
    scenario_dir_name = normalize_scenario_dir_name(scenario_id)
    scenario_root = get_scenarios_root(repo_root, config) / scenario_dir_name
    state_file = scenario_root / "state" / "runtime.json"
    existing_state = load_runtime_state(state_file)
    bootstrap_logger = setup_logger("dev-bootstrap", ensure_dir(repo_root / "tmp") / "bootstrap.log")

    if existing_state and not args.force_retry:
        runtime_paths = build_runtime_paths(scenario_root)
        logger, log_file = prepare_logger(runtime_paths, scenario_dir_name)
        pid = existing_state.get("agent", {}).get("pid")
        if is_process_running(pid):
            logger.info("检测到已有运行中的 Agent 任务，PID=%s。", pid)
            if args.resume or args.wait:
                logger.info("复用已有运行状态，不重复下发。")
                return 0
            logger.info("如需重试请使用 --force-retry。")
            return 0

        if existing_state.get("status") in {"completed", "pushed"}:
            logger.info("该场景已完成，结果文件: %s", existing_state.get("result_json"))
            return 0

        logger.warning("检测到历史状态但 Agent 已不在运行。将状态视为可恢复/可重试。")

    branch_name = app_info["base_branch"]
    ensure_base_branch(repo_root, config, branch_name, bootstrap_logger, args.dry_run)
    scenario_root = prepare_scenario_root(repo_root, config, scenario_dir_name, bootstrap_logger, args.dry_run)
    runtime_paths = build_runtime_paths(scenario_root)
    logger, log_file = prepare_logger(runtime_paths, scenario_dir_name)

    logger.info("开始执行 APP 场景自动化编排")
    logger.info("场景输入: %s", input_path)
    logger.info("识别 APP 类型: %s (%s)", app_key, app_info.get("display_name", app_key))
    logger.info("目标场景目录: %s", scenario_root)

    template_path = resolve_path(repo_root, config["paths"]["task_template"])
    template_text = read_text(template_path)
    build_command = config["build"]["command"]
    scenarios_root_posix = config["paths"]["scenarios_root"].replace("\\", "/")
    build_target = f"{scenarios_root_posix}/{scenario_dir_name}"
    prompt_variables = build_prompt_variables(
        input_path=input_path,
        scenario_payload=scenario_payload,
        app_key=app_key,
        app_info=app_info,
        branch_name=branch_name,
        scenario_dir_name=scenario_dir_name,
        scenario_root=scenario_root,
        runtime_paths=runtime_paths,
        build_command=build_command,
        build_target=build_target,
    )
    task_prompt = render_template(template_text, prompt_variables)
    task_prompt_path = write_task_prompt_snapshot(runtime_paths, task_prompt)
    logger.info("已输出任务 Prompt 快照: %s", task_prompt_path)
    scenario_question = str(scenario_payload.get("question") or scenario_payload.get("prompt") or "").strip()

    task_started_at = now_local_iso()
    state = initialize_inspection(
        {
            "pipeline_key": scenario_dir_name,
            "pipeline_type": "scenario",
            "pipeline_name": scenario_dir_name,
            "pipeline_root": str(scenario_root),
            "target_build": build_target,
            "scenario_id": scenario_id,
            "scenario_key": scenario_dir_name,
            "scenario_input": str(input_path),
            "scenario_question": scenario_question,
            "app_type": app_key,
            "app_display_name": app_info.get("display_name", app_key),
            "base_branch": branch_name,
            "branch_name": branch_name,
            "scenario_branch": branch_name,
            "status": "initialized",
            "created_at": task_started_at,
            "runtime_started_at": task_started_at,
            "runtime_ended_at": None,
            "updated_at": task_started_at,
            "log_file": str(log_file),
            "mock_data_dir": str(runtime_paths["mock_dir"]),
            "spec_dir": str(runtime_paths["spec_dir"]),
            "result_json": str(runtime_paths["result_json"]),
            "state_file": str(state_file),
            "web": {},
            "agent": {
                "type": config["agent"]["active"],
                "runtime": build_agent_runtime_info(repo_root, config),
                "log_path": str(runtime_paths["logs_dir"] / f"agent-{scenario_dir_name}-{utc_now_compact()}.log"),
                "command": [],
                "pid": None,
                "started_at": None,
            },
        }
    )
    update_runtime_state(state_file, state, logger)

    logger.info("Git 基础分支与场景目录已就绪。")
    state["pipeline_root"] = str(scenario_root)
    state = update_state_status(state, "git_ready")
    update_runtime_state(state_file, state, logger)

    agent_definition = config["agent"]["definitions"][config["agent"]["active"]]
    task_via_stdin = bool(agent_definition.get("task_via_stdin", True))
    agent_command, extra_env = instantiate_agent_command(agent_definition, task_prompt, prompt_variables)
    state = dispatch_agent(
        repo_root,
        state,
        agent_command,
        task_prompt,
        extra_env,
        logger,
        args.dry_run,
        task_via_stdin=task_via_stdin,
    )
    state["updated_at"] = now_local_iso()
    update_runtime_state(state_file, state, logger)

    if not args.no_web:
        start_web_console(repo_root, config_path, scenario_dir_name, logger, args.dry_run)
        web_url = wait_log_web_url(state_file, logger)
        if web_url:
            logger.info("Web 控制台已就绪，访问地址: %s", web_url)
        else:
            web_log = repo_root / "scenarios" / scenario_dir_name / "logs" / "web-console.log"
            logger.warning(
                "Web 子进程在数秒内未把访问地址写入状态文件。请打开日志排查: %s 或见 %s 中的 web 字段。",
                web_log,
                state_file,
            )

    if args.wait and not args.dry_run:
        try:
            wait_for_agent_result(state, state_file, config, logger)
        except KeyboardInterrupt:
            return 130

    logger.info("自动化下发完成。")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"执行失败: {exc}", file=sys.stderr)
        sys.exit(1)
