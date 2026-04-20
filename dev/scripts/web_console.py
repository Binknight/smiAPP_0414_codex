from __future__ import annotations

import argparse
import json
import mimetypes
import os
import socket
import subprocess
import threading
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

from common import (
    configure_stdio,
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


def read_log_tail(path: Path, lines: int) -> str:
    if not path.exists():
        return ""
    content = path.read_text(encoding="utf-8", errors="replace").splitlines()
    return "\n".join(content[-lines:])


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


def compute_progress(state: dict[str, Any]) -> dict[str, Any]:
    inspection = state.get("inspection") or {}
    result_exists = Path(state["result_json"]).exists()
    current = 1
    label = "初始化"
    status = state.get("status")
    if status in {"git_preparing", "git_ready"}:
        current = 2
        label = "Git 准备"
    elif status in {"agent_running"}:
        current = 3
        label = "Agent 运行中"
    elif status in {"inspection_running"} or inspection.get("status") == "running":
        current = 4
        label = "巡检中"
    elif result_exists:
        current = 5
        label = "已产出结果"
    if status == "dry_run":
        current = 6
        label = "dry-run 完成"
    if status in {"pushed", "completed", "build_failed", "agent_exited_without_result", "cancelled", "dry_run_success_detected"}:
        current = 6
        label = {
            "pushed": "已推送",
            "completed": "已完成",
            "build_failed": "构建失败",
            "agent_exited_without_result": "异常结束",
            "cancelled": "已取消",
            "dry_run": "dry-run 完成",
            "dry_run_success_detected": "dry-run 完成",
        }.get(status, "已完成")
    total = 6
    return {
        "currentStep": current,
        "totalSteps": total,
        "percent": int(current / total * 100),
        "label": label,
        "steps": [
            "初始化",
            "Git 准备",
            "Agent 运行中",
            "巡检中",
            "已产出结果",
            "完成",
        ],
    }


def build_task_payload(state_file: Path) -> dict[str, Any]:
    state = load_runtime_state(state_file)
    if not state:
        return {"error": "state_not_found"}
    inspection = state.get("inspection") or {}
    result_json = Path(state["result_json"])
    result_payload = state.get("result_payload")
    if result_payload is None and result_json.exists():
        result_payload = read_json(result_json)
    return {
        "scenarioId": state.get("scenario_id"),
        "scenarioKey": state.get("scenario_key"),
        "scenarioInput": state.get("scenario_input"),
        "appType": state.get("app_type"),
        "appDisplayName": state.get("app_display_name"),
        "baseBranch": state.get("base_branch"),
        "scenarioBranch": state.get("scenario_branch"),
        "status": state.get("status"),
        "createdAt": state.get("created_at"),
        "updatedAt": state.get("updated_at"),
        "logFile": state.get("log_file"),
        "resultJson": state.get("result_json"),
        "resultExists": result_json.exists(),
        "resultPayload": result_payload,
        "agent": {
            "type": state.get("agent", {}).get("type"),
            "pid": state.get("agent", {}).get("pid"),
            "startedAt": state.get("agent", {}).get("started_at"),
            "running": is_process_running(state.get("agent", {}).get("pid")),
            "logPath": state.get("agent", {}).get("log_path"),
            "command": state.get("agent", {}).get("command"),
        },
        "inspection": {
            "status": inspection.get("status"),
            "lastCheckedAt": inspection.get("last_checked_at"),
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
            query = parse_qs(parsed.query)
            tail = int(query.get("tail", ["80"])[0])
            state = load_runtime_state(self.server.state_file) or {}
            payload = {
                "pipelineLog": read_log_tail(Path(state.get("log_file", "")), tail),
                "agentLog": read_log_tail(Path(state.get("agent", {}).get("log_path", "")), tail),
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
            state["cancel_reason"] = "terminated_from_web"
            inspection = state.get("inspection") or {}
            inspection["status"] = "cancelled"
            inspection["message"] = "任务已由控制台终止"
            inspection["last_checked_at"] = now_local_iso()
            state["inspection"] = inspection
            state["updated_at"] = now_local_iso()
            update_runtime_state(self.server.state_file, state, self.server.logger)
            self.server.stop_event.set()
            self._send_json({"ok": True, "terminated": running, "status": state["status"]})
            return

        if parsed.path == "/api/console/shutdown":
            mark_web_stopped(self.server.state_file, self.server.logger)
            self._send_json({"ok": True, "message": "console_shutting_down"})
            self.server.stop_event.set()
            threading.Thread(target=self.server.shutdown, daemon=True).start()
            return

        self.send_error(HTTPStatus.NOT_FOUND)
        return

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
    logger.info("Web 控制台已启动: http://%s:%s", host, port)
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        logger.info("收到中断信号，准备关闭 Web 控制台。")
    finally:
        stop_event.set()
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
