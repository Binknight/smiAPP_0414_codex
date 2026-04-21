from __future__ import annotations

import argparse
import json
import mimetypes
import os
import signal
import socket
import subprocess
import threading
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from common import (
    configure_stdio,
    format_display_time,
    ensure_dir,
    is_process_running,
    load_runtime_state,
    now_local_iso,
    read_json,
    resolve_path,
    setup_stream_logger,
    update_runtime_state,
    windows_subprocess_kwargs,
)
from pipeline_monitor_lib import handle_state_file, run_loop


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="dev 本地任务控制台")
    parser.add_argument("--config", default="dev/config/pipeline.config.json", help="主配置文件路径")
    parser.add_argument("--state-file", required=True, help="当前任务的 runtime state 文件")
    parser.add_argument("--host", default="127.0.0.1", help="Web 服务监听地址")
    parser.add_argument("--port", type=int, default=8765, help="Web 服务监听端口")
    parser.add_argument("--dry-run", action="store_true", help="巡检使用 dry-run 模式")
    return parser.parse_args()


def load_config(config_path: Path) -> dict[str, Any]:
    return read_json(config_path)


def prepare_web_logger() -> Any:
    return setup_stream_logger("dev-web-console")


def find_available_port(host: str, starting_port: int, attempts: int = 20) -> int:
    for port in range(starting_port, starting_port + attempts):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            if sock.connect_ex((host, port)) != 0:
                return port
    raise RuntimeError(f"无法找到可用端口，起始端口={starting_port}")


def read_log_content(path: Path) -> str:
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def terminate_pid(pid: int) -> bool:
    result = subprocess.run(
        ["taskkill", "/PID", str(pid), "/T", "/F"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
        **windows_subprocess_kwargs(),
    )
    return result.returncode == 0


def list_web_console_pids_for_state(state_file: Path) -> list[int]:
    normalized = str(state_file.resolve()).lower()
    script_name = str((Path(__file__).resolve())).lower()
    current_pid = os.getpid()
    process_query = subprocess.run(
        [
            "powershell",
            "-Command",
            (
                "Get-CimInstance Win32_Process | "
                "Where-Object { $_.Name -eq 'python.exe' -or $_.Name -eq 'py.exe' } | "
                "Select-Object ProcessId, CommandLine | ConvertTo-Json -Compress"
            ),
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
        **windows_subprocess_kwargs(),
    )
    if process_query.returncode != 0 or not process_query.stdout.strip():
        return []

    try:
        payload = json.loads(process_query.stdout)
    except json.JSONDecodeError:
        return []

    if isinstance(payload, dict):
        payload = [payload]

    matches: list[int] = []
    for item in payload:
        pid = int(item.get("ProcessId") or 0)
        command_line = str(item.get("CommandLine") or "").lower()
        if not pid or pid == current_pid:
            continue
        if "web_console.py" not in command_line:
            continue
        if script_name not in command_line:
            continue
        if normalized not in command_line:
            continue
        matches.append(pid)
    return matches


def stop_pid(pid: int) -> bool:
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        return False
    return True


def stop_other_web_consoles(state_file: Path, logger: Any) -> list[int]:
    stopped: list[int] = []
    for pid in list_web_console_pids_for_state(state_file):
        if stop_pid(pid):
            stopped.append(pid)
    if stopped:
        logger.info("已停止同任务的历史 Web 控制台进程: %s", ", ".join(str(pid) for pid in stopped))
    return stopped


def compute_progress(state: dict[str, Any]) -> dict[str, Any]:
    inspection = state.get("inspection") or {}
    result_exists = Path(state["result_json"]).exists()
    current = 1
    label = "任务初始化"
    status = state.get("status")

    if status in {"git_preparing", "git_ready"}:
        current = 2
        label = "仿真基线准备"
    elif status in {"agent_running"}:
        current = 3
        label = "Agent 运行时"
    elif status in {"inspection_running"} or inspection.get("status") == "running":
        current = 4
        label = "状态巡检"
    elif result_exists:
        current = 5
        label = "结果输出"

    if status in {"dry_run", "pushed", "completed", "build_failed", "agent_exited_without_result", "cancelled", "dry_run_success_detected"}:
        current = 6
        label = "完成"

    total = 6
    return {
        "currentStep": current,
        "totalSteps": total,
        "percent": int(current / total * 100),
        "label": label,
        "steps": [
            "任务初始化",
            "仿真基线准备",
            "Agent 运行时",
            "状态巡检",
            "结果输出",
            "完成",
        ],
    }


def infer_scenario_question(state: dict[str, Any]) -> str | None:
    question = state.get("scenario_question")
    if question:
        return str(question)
    scenario_input = state.get("scenario_input")
    if not scenario_input:
        return None
    input_path = Path(str(scenario_input))
    if not input_path.exists():
        return None
    try:
        payload = read_json(input_path)
    except Exception:
        return None
    return payload.get("question") or payload.get("prompt")


def build_agent_runtime_payload(state: dict[str, Any]) -> dict[str, Any]:
    runtime = dict(state.get("agent", {}).get("runtime") or {})
    agent_state = state.get("agent") or {}
    session_id = (
        runtime.get("session_id")
        or runtime.get("sessionId")
        or agent_state.get("session_id")
        or agent_state.get("sessionId")
        or os.environ.get("CODEX_SESSION_ID")
        or os.environ.get("OPENAI_SESSION_ID")
    )
    runtime.setdefault("workspace", str(Path(__file__).resolve().parents[2]))
    runtime.setdefault("name", "codex cli")
    runtime.setdefault("model", os.environ.get("CODEX_MODEL", "gpt-5.4"))
    runtime.setdefault("provider", os.environ.get("CODEX_PROVIDER", "openai"))
    runtime.setdefault("approval_policy", os.environ.get("CODEX_APPROVAL_POLICY", "never"))
    runtime.setdefault("sandbox_mode", os.environ.get("CODEX_SANDBOX_MODE", "danger-full-access"))
    runtime.setdefault("reasoning_effort", os.environ.get("CODEX_REASONING_EFFORT", "medium"))
    runtime.setdefault("reasoning_summary", os.environ.get("CODEX_REASONING_SUMMARY", "none"))
    if session_id:
        runtime["session_id"] = session_id
    return runtime


def build_task_payload(state_file: Path) -> dict[str, Any]:
    state = load_runtime_state(state_file)
    if not state:
        return {"error": "state_not_found"}
    inspection = state.get("inspection") or {}
    result_json = Path(state["result_json"])
    result_payload = state.get("result_payload")
    if result_payload is None and result_json.exists():
        result_payload = read_json(result_json)
    agent_runtime = build_agent_runtime_payload(state)
    runtime_started_at = state.get("runtime_started_at") or state.get("created_at")
    runtime_ended_at = state.get("runtime_ended_at")
    if runtime_ended_at is None and state.get("status") in {
        "cancelled",
        "pushed",
        "completed",
        "build_failed",
        "agent_exited_without_result",
        "dry_run_success_detected",
    }:
        runtime_ended_at = (
            state.get("cancelled_at")
            or state.get("pushed_at")
            or state.get("completed_at")
            or state.get("updated_at")
        )
    return {
        "scenarioId": state.get("scenario_id"),
        "scenarioKey": state.get("scenario_key"),
        "scenarioInput": state.get("scenario_input"),
        "scenarioQuestion": infer_scenario_question(state),
        "appType": state.get("app_type"),
        "appDisplayName": state.get("app_display_name"),
        "baseBranch": state.get("base_branch"),
        "scenarioBranch": state.get("scenario_branch"),
        "status": state.get("status"),
        "createdAt": format_display_time(state.get("created_at")),
        "updatedAt": format_display_time(state.get("updated_at")),
        "runtimeStartedAt": format_display_time(runtime_started_at),
        "runtimeEndedAt": format_display_time(runtime_ended_at),
        "logFile": state.get("log_file"),
        "resultJson": state.get("result_json"),
        "resultExists": result_json.exists(),
        "resultPayload": result_payload,
        "agent": {
            "type": state.get("agent", {}).get("type"),
            "pid": state.get("agent", {}).get("pid"),
            "startedAt": format_display_time(state.get("agent", {}).get("started_at")),
            "running": is_process_running(state.get("agent", {}).get("pid")),
            "logPath": state.get("agent", {}).get("log_path"),
            "command": state.get("agent", {}).get("command"),
            "workspace": agent_runtime.get("workspace"),
            "sessionId": agent_runtime.get("session_id"),
            "runtime": agent_runtime,
        },
        "inspection": {
            "status": inspection.get("status"),
            "lastCheckedAt": format_display_time(inspection.get("last_checked_at")),
            "cycleCount": inspection.get("cycle_count"),
            "message": inspection.get("message"),
        },
        "web": state.get("web") or {},
        "progress": compute_progress(state),
    }


def mark_web_stopped(state_file: Path, logger: Any) -> None:
    state = load_runtime_state(state_file)
    if not state:
        return
    web = state.get("web") or {}
    if web:
        web["stopped_at"] = now_local_iso()
        web["pid"] = None
        state["web"] = web
    state["updated_at"] = now_local_iso()
    update_runtime_state(state_file, state, logger)


class ConsoleHandler(BaseHTTPRequestHandler):
    server_version = "DevConsole/1.0"

    def _send_json(self, payload: dict[str, Any], status: int = HTTPStatus.OK) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_file(self, path: Path) -> None:
        if not path.exists():
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        content = path.read_bytes()
        content_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(content)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/api/task/current":
            self._send_json(build_task_payload(self.server.state_file))
            return
        if parsed.path == "/api/task/current/progress":
            task = build_task_payload(self.server.state_file)
            self._send_json(task.get("progress") or {})
            return
        if parsed.path == "/api/task/current/logs":
            state = load_runtime_state(self.server.state_file) or {}
            payload = {
                "pipelineLog": read_log_content(Path(state.get("log_file", ""))),
                "agentLog": read_log_content(Path(state.get("agent", {}).get("log_path", ""))),
            }
            self._send_json(payload)
            return

        static_path = self.server.static_root / parsed.path.lstrip("/")
        if parsed.path in {"/", ""}:
            static_path = self.server.static_root / "index.html"
        resolved_static = static_path.resolve()
        static_root = self.server.static_root.resolve()
        if resolved_static.is_file() and (resolved_static == static_root or static_root in resolved_static.parents):
            self._send_file(static_path)
            return
        self.send_error(HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/api/task/current/terminate":
            state = load_runtime_state(self.server.state_file)
            if not state:
                self._send_json({"ok": False, "message": "state_not_found"}, status=HTTPStatus.NOT_FOUND)
                return
            pid = state.get("agent", {}).get("pid")
            running = is_process_running(pid)
            if running:
                terminate_pid(int(pid))
            state["status"] = "cancelled"
            state["cancelled_at"] = now_local_iso()
            state["runtime_ended_at"] = state["cancelled_at"]
            state["cancel_reason"] = "terminated_from_web"
            inspection = state.get("inspection") or {}
            inspection["status"] = "cancelled"
            inspection["message"] = "任务已由控制台终止"
            inspection["last_checked_at"] = inspection.get("last_checked_at") or state["cancelled_at"]
            state["inspection"] = inspection
            state["updated_at"] = state["cancelled_at"]
            update_runtime_state(self.server.state_file, state, self.server.logger)
            stopped_pids = stop_other_web_consoles(self.server.state_file, self.server.logger)
            self.server.stop_event.set()
            self._send_json(
                {
                    "ok": True,
                    "terminated": running,
                    "status": state["status"],
                    "stoppedConsolePids": stopped_pids,
                }
            )
            return

        if parsed.path == "/api/console/shutdown":
            mark_web_stopped(self.server.state_file, self.server.logger)
            self._send_json({"ok": True, "message": "console_shutting_down"})
            self.server.stop_event.set()
            threading.Thread(target=self.server.shutdown, daemon=True).start()
            return

        self.send_error(HTTPStatus.NOT_FOUND)

    def log_message(self, format: str, *args: Any) -> None:
        self.server.logger.info("web %s - %s", self.address_string(), format % args)


class ConsoleServer(ThreadingHTTPServer):
    def __init__(
        self,
        server_address: tuple[str, int],
        handler_class: type[BaseHTTPRequestHandler],
        *,
        state_file: Path,
        static_root: Path,
        logger: Any,
        stop_event: threading.Event,
    ) -> None:
        super().__init__(server_address, handler_class)
        self.state_file = state_file
        self.static_root = static_root.resolve()
        self.logger = logger
        self.stop_event = stop_event


def mark_web_state(state_file: Path, logger: Any, host: str, port: int) -> None:
    state = load_runtime_state(state_file)
    if not state:
        return
    state["web"] = {
        "host": host,
        "port": port,
        "url": f"http://{host}:{port}",
        "started_at": now_local_iso(),
        "pid": os.getpid(),
    }
    update_runtime_state(state_file, state, logger)


def start_inspection_thread(
    repo_root: Path,
    config: dict[str, Any],
    state_file: Path,
    logger: Any,
    dry_run: bool,
    stop_event: threading.Event,
) -> threading.Thread:
    thread = threading.Thread(
        target=run_loop,
        kwargs={
            "repo_root": repo_root,
            "config": config,
            "state_arg": str(state_file),
            "logger": logger,
            "dry_run": dry_run,
            "stop_event": stop_event,
        },
        daemon=True,
        name="inspection-loop",
    )
    thread.start()
    return thread


def main() -> int:
    configure_stdio()
    args = parse_args()
    config_path = Path(args.config).resolve()
    config = load_config(config_path)
    repo_root = resolve_path(config_path.parent.parent.parent, config["paths"]["repo_root"])
    state_file = resolve_path(repo_root, args.state_file)
    logger = prepare_web_logger()
    host = args.host
    port = find_available_port(host, args.port)
    static_root = ensure_dir(repo_root / "dev" / "frontend")
    stop_event = threading.Event()

    stop_other_web_consoles(state_file, logger)

    handle_state_file(repo_root, config, state_file, logger, args.dry_run)
    start_inspection_thread(repo_root, config, state_file, logger, args.dry_run, stop_event)
    server = ConsoleServer(
        (host, port),
        ConsoleHandler,
        state_file=state_file,
        static_root=static_root,
        logger=logger,
        stop_event=stop_event,
    )
    mark_web_state(state_file, logger, host, port)
    logger.info("Web æŽ§åˆ¶å°å·²å¯åŠ¨: http://%s:%s", host, port)
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        logger.info("æ”¶åˆ°ä¸­æ–­ä¿¡å·ï¼Œå‡†å¤‡å…³é—­ Web æŽ§åˆ¶å°ã€‚")
    finally:
        stop_event.set()
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

