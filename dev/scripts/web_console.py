from __future__ import annotations

import argparse
import json
import mimetypes
import os
import re
import signal
import socket
import subprocess
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

from common import (
    configure_stdio,
    detect_build_success,
    ensure_dir,
    format_display_time,
    is_process_running,
    load_runtime_state,
    now_local_iso,
    read_json,
    resolve_path,
    setup_logger,
    setup_stream_logger,
    update_runtime_state,
    windows_subprocess_kwargs,
)
from pipeline_monitor_lib import collect_state_files, handle_state_file, run_loop

REPO_ROOT = Path(__file__).resolve().parents[2]
SUCCESS_STATUSES = {"pushed", "completed", "dry_run_success_detected"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="dev 本地任务控制台")
    parser.add_argument("--config", default="dev/config/pipeline.config.json", help="主配置文件路径")
    parser.add_argument("--selected", default="baseApp", help="默认选中的 pipeline")
    parser.add_argument("--host", default="127.0.0.1", help="Web 服务监听地址")
    parser.add_argument("--port", type=int, default=8765, help="Web 服务监听端口")
    parser.add_argument(
        "--log-file",
        default=None,
        help="将 Web 服务日志写入该文件（子进程/无控制台时便于排错）",
    )
    parser.add_argument("--dry-run", action="store_true", help="巡检使用 dry-run 模式")
    return parser.parse_args()


def load_config(config_path: Path) -> dict[str, Any]:
    return read_json(config_path)


def prepare_web_logger(log_path: Path | None) -> Any:
    if log_path is None:
        return setup_stream_logger("dev-web-console")
    ensure_dir(log_path.parent)
    return setup_logger("dev-web-console", log_path)


def find_available_port(host: str, starting_port: int, attempts: int = 20) -> int:
    for port in range(starting_port, starting_port + attempts):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            if sock.connect_ex((host, port)) != 0:
                return port
    raise RuntimeError(f"无法找到可用端口，起始端口={starting_port}")


def read_log_content(path: Path) -> str:
    if not path.exists() or not path.is_file():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def get_safe_tmp_name(target_build: str) -> str:
    return target_build.replace("/", "-").replace("\\", "-").strip("-").lower()


def get_workspace_output_dir(target_build: str) -> Path:
    return REPO_ROOT / "tmp" / get_safe_tmp_name(target_build) / "entry" / "build" / "default" / "outputs" / "default"


def resolve_target_build_root(target_build: str) -> Path:
    return resolve_path(REPO_ROOT, target_build)


def list_artifact_candidates(target_build: str) -> list[Path]:
    candidates: list[Path] = []
    workspace_output = get_workspace_output_dir(target_build)
    if workspace_output.exists():
        candidates.extend(sorted(workspace_output.glob("*.hap"), key=lambda item: item.stat().st_mtime, reverse=True))

    source_output = resolve_target_build_root(target_build) / "entry" / "build" / "default" / "outputs" / "default"
    if source_output.exists():
        candidates.extend(sorted(source_output.glob("*.hap"), key=lambda item: item.stat().st_mtime, reverse=True))
    return candidates


def build_artifact_payload(
    target_build: str,
    state: dict[str, Any] | None,
    result_payload: dict[str, Any] | None,
    pipeline_key: str,
) -> dict[str, Any] | None:
    success = False
    if state:
        success = state.get("status") in SUCCESS_STATUSES
    if not success and result_payload:
        success = detect_build_success(result_payload, ["success", "succeeded", "ok", "passed", "true"])
    if not success and pipeline_key != "baseApp":
        return None

    candidates: list[Path] = []
    artifact_path = None if not result_payload else result_payload.get("artifactPath") or result_payload.get("artifact_path")
    if artifact_path:
        candidates.append(resolve_path(REPO_ROOT, str(artifact_path)))
    candidates.extend(list_artifact_candidates(target_build))

    seen: set[str] = set()
    for candidate in candidates:
        if not candidate.exists() or candidate.suffix.lower() != ".hap":
            continue
        key = str(candidate.resolve()).lower()
        if key in seen:
            continue
        seen.add(key)
        return {
            "path": str(candidate.resolve()),
            "name": candidate.name,
            "sizeBytes": candidate.stat().st_size,
            "downloadUrl": f"/api/pipelines/current/artifact?pipeline={pipeline_key}",
        }
    return None


def extract_session_id_from_agent_log(log_path: str | None) -> str | None:
    if not log_path:
        return None
    path = Path(log_path)
    if not path.exists():
        return None
    try:
        with path.open("r", encoding="utf-8", errors="replace") as handle:
            for _, line in zip(range(40), handle):
                match = re.search(r"session id:\s*([A-Za-z0-9-]+)", line, re.IGNORECASE)
                if match:
                    return match.group(1)
    except OSError:
        return None
    return None


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


def list_web_console_pids(logger: Any) -> list[int]:
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
        logger.warning("无法解析 Web 控制台进程列表。")
        return []

    if isinstance(payload, dict):
        payload = [payload]

    script_name = str(Path(__file__).resolve()).lower()
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
        matches.append(pid)
    return matches


def stop_pid(pid: int) -> bool:
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        return False
    return True


def stop_other_web_consoles(logger: Any) -> list[int]:
    stopped: list[int] = []
    for pid in list_web_console_pids(logger):
        if stop_pid(pid):
            stopped.append(pid)
    if stopped:
        logger.info("已停止历史 Web 控制台进程: %s", ", ".join(str(pid) for pid in stopped))
    return stopped


def compute_progress(state: dict[str, Any] | None, result_exists: bool) -> dict[str, Any]:
    if not state:
        current = 1 if not result_exists else 6
        return {
            "currentStep": current,
            "totalSteps": 6,
            "percent": int(current / 6 * 100),
            "label": "已构建" if result_exists else "未启动流水线",
            "steps": ["任务初始化", "仿真基线准备", "Agent 运行时", "状态巡检", "结果输出", "完成"],
        }

    inspection = state.get("inspection") or {}
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

    return {
        "currentStep": current,
        "totalSteps": 6,
        "percent": int(current / 6 * 100),
        "label": label,
        "steps": ["任务初始化", "仿真基线准备", "Agent 运行时", "状态巡检", "结果输出", "完成"],
    }


def build_agent_runtime_payload(state: dict[str, Any] | None) -> dict[str, Any]:
    runtime = dict((state or {}).get("agent", {}).get("runtime") or {})
    agent_state = (state or {}).get("agent") or {}
    session_id = (
        runtime.get("session_id")
        or runtime.get("sessionId")
        or agent_state.get("session_id")
        or agent_state.get("sessionId")
        or extract_session_id_from_agent_log(agent_state.get("log_path"))
        or os.environ.get("CODEX_SESSION_ID")
        or os.environ.get("OPENAI_SESSION_ID")
        or os.environ.get("OPENCODE_SESSION_ID")
    )
    runtime.setdefault("workspace", str(REPO_ROOT))
    _atype = (agent_state.get("type") or "codex_cli") if (state) else "codex_cli"
    runtime.setdefault("name", str(_atype).replace("_", " ").lower())
    runtime.setdefault("model", os.environ.get("CODEX_MODEL", "gpt-5.4"))
    runtime.setdefault("provider", os.environ.get("CODEX_PROVIDER", "openai"))
    runtime.setdefault("approval_policy", os.environ.get("CODEX_APPROVAL_POLICY", "never"))
    runtime.setdefault("sandbox_mode", os.environ.get("CODEX_SANDBOX_MODE", "danger-full-access"))
    runtime.setdefault("reasoning_effort", os.environ.get("CODEX_REASONING_EFFORT", "medium"))
    runtime.setdefault("reasoning_summary", os.environ.get("CODEX_REASONING_SUMMARY", "none"))
    if session_id:
        runtime["session_id"] = session_id
        runtime["sessionId"] = session_id
    return runtime


def get_pipeline_roots(repo_root: Path, config: dict[str, Any]) -> tuple[Path, Path]:
    baseline_root = ensure_dir(resolve_path(repo_root, config["paths"]["baseline_root"]))
    scenarios_root = ensure_dir(resolve_path(repo_root, config["paths"]["scenarios_root"]))
    return baseline_root, scenarios_root


def scenario_target_build(config: dict[str, Any], scenario_name: str) -> str:
    """config 中 scenarios 根路径的 POSIX 形式，供 targetBuild / build_artifact 使用。
    单独函数是为了避免在 f-string 表达式里写 .replace('\\\\', '/')（部分 Python 版本会 SyntaxError）。"""
    root = str(config["paths"]["scenarios_root"]).replace("\\", "/")
    return f"{root}/{scenario_name}"


def get_state_file_for_pipeline(pipeline_root: Path) -> Path | None:
    state_file = pipeline_root / "state" / "runtime.json"
    return state_file if state_file.exists() else None


def build_base_pipeline_summary(baseline_root_str: str) -> dict[str, Any]:
    return {
        "key": "baseApp",
        "name": "baseApp",
        "type": "baseApp",
        "targetBuild": baseline_root_str,
        "root": baseline_root_str,
        "status": "ready",
        "branchName": None,
        "updatedAt": format_display_time(now_local_iso()),
        "hasState": False,
        "hasArtifact": False,
    }


def list_pipeline_summaries(repo_root: Path, config: dict[str, Any]) -> list[dict[str, Any]]:
    baseline_root, scenarios_root = get_pipeline_roots(repo_root, config)
    baseline_root_str = config["paths"]["baseline_root"]
    items = [build_base_pipeline_summary(baseline_root_str)]
    for app_type_dir in sorted(scenarios_root.iterdir()):
        if not app_type_dir.is_dir():
            continue
        for scenario_root in sorted(app_type_dir.iterdir()):
            if not scenario_root.is_dir():
                continue
            scenario_key = f"{app_type_dir.name}/{scenario_root.name}"
            state_file = get_state_file_for_pipeline(scenario_root)
            state = load_runtime_state(state_file) if state_file else None
            tb = scenario_target_build(config, scenario_key)
            items.append(
                {
                    "key": scenario_key,
                    "name": scenario_key,
                    "type": "scenario",
                    "targetBuild": tb,
                    "root": str(scenario_root),
                    "status": (state or {}).get("status") or "idle",
                    "branchName": (state or {}).get("baseline_dir"),
                    "updatedAt": format_display_time((state or {}).get("updated_at")),
                    "hasState": bool(state),
                    "hasArtifact": bool(build_artifact_payload(tb, state, (state or {}).get("result_payload"), scenario_key)),
                }
            )
    return items


def get_pipeline_context(repo_root: Path, config: dict[str, Any], pipeline_key: str) -> dict[str, Any]:
    baseline_root, scenarios_root = get_pipeline_roots(repo_root, config)
    baseline_root_str = config["paths"]["baseline_root"]
    if pipeline_key == "baseApp":
        return {
            "key": "baseApp",
            "name": "baseApp",
            "type": "baseApp",
            "root": baseline_root_str,
            "target_build": baseline_root_str,
            "state_file": None,
        }

    scenario_root = scenarios_root / pipeline_key
    if not scenario_root.exists():
        raise FileNotFoundError(f"未找到 pipeline: {pipeline_key}")
    return {
        "key": pipeline_key,
        "name": pipeline_key,
        "type": "scenario",
        "root": scenario_root,
        "target_build": scenario_target_build(config, pipeline_key),
        "state_file": get_state_file_for_pipeline(scenario_root),
    }


def build_synthetic_payload(context: dict[str, Any]) -> dict[str, Any]:
    artifact = build_artifact_payload(context["target_build"], None, None, context["key"])
    progress = compute_progress(None, artifact is not None)
    return {
        "pipelineKey": context["key"],
        "pipelineType": context["type"],
        "pipelineName": context["name"],
        "pipelineRoot": str(context["root"]),
        "scenarioId": context["key"],
        "scenarioKey": context["key"],
        "scenarioInput": None,
        "scenarioQuestion": None,
        "appType": None,
        "appDisplayName": None,
        "baselineDir": None,
        "status": "ready" if artifact else "idle",
        "createdAt": None,
        "updatedAt": format_display_time(now_local_iso()),
        "runtimeStartedAt": None,
        "runtimeEndedAt": None,
        "logFile": None,
        "resultJson": None,
        "resultExists": False,
        "resultPayload": None,
        "artifact": artifact,
        "agent": {
            "type": None,
            "pid": None,
            "startedAt": None,
            "running": False,
            "logPath": None,
            "command": None,
            "workspace": str(REPO_ROOT),
            "sessionId": None,
            "runtime": build_agent_runtime_payload(None),
        },
        "inspection": {
            "status": "idle",
            "lastCheckedAt": None,
            "cycleCount": 0,
            "message": "该 pipeline 尚未启动自动化流水线",
        },
        "web": {},
        "progress": progress,
        "targetBuild": context["target_build"],
    }


def build_task_payload(repo_root: Path, config: dict[str, Any], pipeline_key: str) -> dict[str, Any]:
    context = get_pipeline_context(repo_root, config, pipeline_key)
    state_file = context["state_file"]
    if not state_file:
        return build_synthetic_payload(context)

    state = load_runtime_state(state_file)
    if not state:
        return build_synthetic_payload(context)

    result_json = Path(state["result_json"])
    result_payload = state.get("result_payload")
    if result_payload is None and result_json.exists():
        result_payload = read_json(result_json)
    artifact = build_artifact_payload(context["target_build"], state, result_payload, pipeline_key)
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
        "pipelineKey": state.get("pipeline_key") or pipeline_key,
        "pipelineType": state.get("pipeline_type") or context["type"],
        "pipelineName": state.get("pipeline_name") or pipeline_key,
        "pipelineRoot": state.get("pipeline_root") or str(context["root"]),
        "scenarioId": state.get("scenario_id"),
        "scenarioKey": state.get("scenario_key"),
        "scenarioInput": state.get("scenario_input"),
        "scenarioQuestion": state.get("scenario_question"),
        "appType": state.get("app_type"),
        "appDisplayName": state.get("app_display_name"),
        "baselineDir": state.get("baseline_dir"),
        "status": state.get("status"),
        "createdAt": format_display_time(state.get("created_at")),
        "updatedAt": format_display_time(state.get("updated_at")),
        "runtimeStartedAt": format_display_time(runtime_started_at),
        "runtimeEndedAt": format_display_time(runtime_ended_at),
        "logFile": state.get("log_file"),
        "resultJson": state.get("result_json"),
        "resultExists": result_json.exists(),
        "resultPayload": result_payload,
        "artifact": artifact,
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
            "status": (state.get("inspection") or {}).get("status"),
            "lastCheckedAt": format_display_time((state.get("inspection") or {}).get("last_checked_at")),
            "cycleCount": (state.get("inspection") or {}).get("cycle_count"),
            "message": (state.get("inspection") or {}).get("message"),
        },
        "web": state.get("web") or {},
        "progress": compute_progress(state, result_json.exists()),
        "targetBuild": context["target_build"],
    }


def get_selected_pipeline(handler: "ConsoleHandler") -> str:
    parsed = urlparse(handler.path)
    query = parse_qs(parsed.query)
    return query.get("pipeline", [handler.server.selected])[0]


def mark_web_state(state_file: Path | None, logger: Any, host: str, port: int) -> None:
    if not state_file:
        return
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


def mark_web_stopped(state_file: Path | None, logger: Any) -> None:
    if not state_file:
        return
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
    server_version = "DevConsole/2.0"

    def _send_json(self, payload: dict[str, Any] | list[Any], status: int = HTTPStatus.OK) -> None:
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

    def _send_download_file(self, path: Path) -> None:
        if not path.exists():
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        content = path.read_bytes()
        content_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Content-Disposition", f'attachment; filename="{path.name}"')
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(content)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        pipeline_key = get_selected_pipeline(self)
        if parsed.path == "/api/pipelines":
            payload = {
                "selected": pipeline_key,
                "items": list_pipeline_summaries(self.server.repo_root, self.server.config),
            }
            self._send_json(payload)
            return
        if parsed.path == "/api/pipelines/current":
            self._send_json(build_task_payload(self.server.repo_root, self.server.config, pipeline_key))
            return
        if parsed.path == "/api/pipelines/current/logs":
            context = get_pipeline_context(self.server.repo_root, self.server.config, pipeline_key)
            state = load_runtime_state(context["state_file"]) if context["state_file"] else {}
            payload = {
                "pipelineLog": read_log_content(Path((state or {}).get("log_file", ""))),
                "agentLog": read_log_content(Path(((state or {}).get("agent", {}) or {}).get("log_path", ""))),
            }
            self._send_json(payload)
            return
        if parsed.path == "/api/pipelines/current/artifact":
            task = build_task_payload(self.server.repo_root, self.server.config, pipeline_key)
            artifact = task.get("artifact") or {}
            path_value = artifact.get("path")
            artifact_path = Path(str(path_value)).resolve() if path_value else None
            if artifact_path is None or not artifact_path.exists():
                self.send_error(HTTPStatus.NOT_FOUND)
                return
            self._send_download_file(artifact_path)
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
        pipeline_key = get_selected_pipeline(self)
        if parsed.path == "/api/pipelines/current/terminate":
            context = get_pipeline_context(self.server.repo_root, self.server.config, pipeline_key)
            state_file = context["state_file"]
            if not state_file:
                self._send_json({"ok": False, "message": "state_not_found"}, status=HTTPStatus.NOT_FOUND)
                return
            state = load_runtime_state(state_file)
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
            update_runtime_state(state_file, state, self.server.logger)
            self._send_json({"ok": True, "terminated": running, "status": state["status"]})
            return

        if parsed.path == "/api/console/shutdown":
            context = get_pipeline_context(self.server.repo_root, self.server.config, self.server.selected)
            mark_web_stopped(context["state_file"], self.server.logger)
            self._send_json({"ok": True, "message": "console_shutting_down"})
            self.server.stop_event.set()
            try:
                self.wfile.flush()
            except OSError:
                pass

            def _exit_after_response() -> None:
                time.sleep(0.25)
                os._exit(0)

            # ThreadingHTTPServer.shutdown()+serve_forever 在部分 Windows 环境无法可靠收束主线程，进程仍挂起
            threading.Thread(target=_exit_after_response, name="dev-web-exit", daemon=True).start()
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
        repo_root: Path,
        config: dict[str, Any],
        selected: str,
        static_root: Path,
        logger: Any,
        stop_event: threading.Event,
    ) -> None:
        super().__init__(server_address, handler_class)
        self.repo_root = repo_root
        self.config = config
        self.selected = selected
        self.static_root = static_root.resolve()
        self.logger = logger
        self.stop_event = stop_event


def start_inspection_thread(
    repo_root: Path,
    config: dict[str, Any],
    logger: Any,
    dry_run: bool,
    stop_event: threading.Event,
) -> threading.Thread:
    thread = threading.Thread(
        target=run_loop,
        kwargs={
            "repo_root": repo_root,
            "config": config,
            "state_arg": None,
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
    log_path: Path | None = Path(args.log_file).resolve() if args.log_file else None
    logger = prepare_web_logger(log_path)
    host = args.host
    port = find_available_port(host, args.port)
    static_root = ensure_dir(repo_root / "dev" / "frontend")
    stop_event = threading.Event()

    stop_other_web_consoles(logger)

    for state_file in collect_state_files(repo_root, config, None):
        handle_state_file(repo_root, config, state_file, logger, args.dry_run)

    start_inspection_thread(repo_root, config, logger, args.dry_run, stop_event)
    server = ConsoleServer(
        (host, port),
        ConsoleHandler,
        repo_root=repo_root,
        config=config,
        selected=args.selected,
        static_root=static_root,
        logger=logger,
        stop_event=stop_event,
    )
    selected_context = get_pipeline_context(repo_root, config, args.selected)
    mark_web_state(selected_context["state_file"], logger, host, port)
    logger.info("Web 控制台已启动: http://%s:%s", host, port)
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        logger.info("收到中断信号，准备关闭 Web 控制台。")
    finally:
        stop_event.set()
        mark_web_stopped(selected_context["state_file"], logger)
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
