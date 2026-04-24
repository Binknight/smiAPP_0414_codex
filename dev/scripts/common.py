from __future__ import annotations

import json
import logging
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

BEIJING_TZ = timezone(timedelta(hours=8), name="UTC+08:00")


def configure_stdio() -> None:
    for stream_name in ("stdout", "stderr"):
        stream = getattr(sys, stream_name, None)
        if stream and hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")


def now_local_iso() -> str:
    return datetime.now(BEIJING_TZ).strftime("%Y-%m-%d %H:%M:%S")


def format_display_time(value: Any) -> str | None:
    if value is None:
        return None

    text = str(value).strip()
    if not text:
        return None

    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        try:
            parsed = datetime.strptime(text, "%Y-%m-%d %H:%M:%S")
        except ValueError:
            return text

    if parsed.tzinfo is not None:
        parsed = parsed.astimezone(BEIJING_TZ)
    return parsed.strftime("%Y-%m-%d %H:%M:%S")


def now_local_compact_minute() -> str:
    return datetime.now(BEIJING_TZ).strftime("%Y%m%d%H%M")


def utc_now_compact() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def resolve_path(repo_root: Path, value: str) -> Path:
    path = Path(value)
    if path.is_absolute():
        return path
    return (repo_root / path).resolve()


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def reset_dir(path: Path) -> Path:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)
    return path


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as handle:
        return json.load(handle)


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def setup_logger(name: str, log_file: Path) -> logging.Logger:
    ensure_dir(log_file.parent)
    logger = logging.getLogger(name)
    logger.setLevel(logging.INFO)
    for handler in logger.handlers[:]:
        handler.close()
    logger.handlers.clear()
    logger.propagate = False

    formatter = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s")

    file_handler = logging.FileHandler(log_file, encoding="utf-8")
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)

    stream_handler = logging.StreamHandler(sys.stdout)
    stream_handler.setFormatter(formatter)
    logger.addHandler(stream_handler)

    return logger


def setup_stream_logger(name: str, stream: Any = None) -> logging.Logger:
    logger = logging.getLogger(name)
    logger.setLevel(logging.INFO)
    logger.handlers.clear()
    logger.propagate = False

    formatter = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s")
    stream_handler = logging.StreamHandler(stream or sys.stdout)
    stream_handler.setFormatter(formatter)
    logger.addHandler(stream_handler)
    return logger


def windows_subprocess_kwargs() -> dict[str, Any]:
    if os.name != "nt":
        return {}
    return {"creationflags": subprocess.CREATE_NO_WINDOW}


def run_command(
    cmd: list[str],
    cwd: Path,
    logger: logging.Logger,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    logger.info("执行命令: %s", format_command(cmd))
    result = subprocess.run(
        cmd,
        cwd=str(cwd),
        text=True,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
        check=False,
        **windows_subprocess_kwargs(),
    )
    if result.stdout.strip():
        logger.info("标准输出:\n%s", result.stdout.rstrip())
    if result.stderr.strip():
        logger.warning("标准错误:\n%s", result.stderr.rstrip())
    if check and result.returncode != 0:
        raise RuntimeError(f"命令执行失败，退出码 {result.returncode}: {format_command(cmd)}")
    return result


def format_command(cmd: list[str]) -> str:
    return subprocess.list2cmdline(cmd)


def render_template(template: str, variables: dict[str, str]) -> str:
    rendered = template
    for key, value in variables.items():
        rendered = rendered.replace(f"{{{{{key}}}}}", value)
    return rendered


def normalize_app_key(config: dict[str, Any], raw_app: str | None) -> tuple[str, dict[str, Any]]:
    app_types = config["git"]["app_types"]
    candidate = (raw_app or "").strip().lower()
    if not candidate:
        candidate = config["git"]["default_base_branch"]

    for key, app_info in app_types.items():
        aliases = {key, *(alias.lower() for alias in app_info.get("aliases", []))}
        if candidate in aliases:
            return key, app_info

    raise ValueError(f"未识别的 app 类型: {raw_app!r}")


def infer_scenario_id(path: Path, padding: int) -> str:
    matches = re.findall(r"(\d+)", path.stem)
    if matches:
        return matches[-1].zfill(padding)

    sanitized = re.sub(r"[^a-zA-Z0-9]+", "-", path.stem).strip("-").lower()
    return sanitized or datetime.now().strftime("%Y%m%d%H%M%S")


def sanitize_name(value: str) -> str:
    return re.sub(r"[^a-zA-Z0-9._-]+", "-", value).strip("-").lower()


def load_runtime_state(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    return read_json(path)


def is_process_running(pid: int | None) -> bool:
    if not pid:
        return False
    result = subprocess.run(
        ["tasklist", "/FI", f"PID eq {pid}"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
        **windows_subprocess_kwargs(),
    )
    return str(pid) in result.stdout


def git_has_local_changes(repo_root: Path) -> bool:
    result = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=str(repo_root),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
        **windows_subprocess_kwargs(),
    )
    return bool(result.stdout.strip())


def ensure_remote(repo_root: Path, git_config: dict[str, Any], logger: logging.Logger) -> None:
    remote_name = git_config["remote_name"]
    remote_url = git_config["remote_url"]
    result = subprocess.run(
        ["git", "remote", "get-url", remote_name],
        cwd=str(repo_root),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
        **windows_subprocess_kwargs(),
    )
    if result.returncode != 0:
        logger.info("检测到远端 %s 不存在，开始自动添加。", remote_name)
        run_command(["git", "remote", "add", remote_name, remote_url], repo_root, logger)
        return

    current_url = result.stdout.strip()
    if current_url != remote_url:
        logger.warning("远端 %s 地址与配置不一致。当前: %s，配置: %s", remote_name, current_url, remote_url)


def update_runtime_state(state_file: Path, state: dict[str, Any], logger: logging.Logger | None = None) -> None:
    write_json(state_file, state)
    if logger:
        logger.info("状态文件已更新: %s", state_file)


def detect_build_success(result_payload: dict[str, Any], success_values: list[str]) -> bool:
    candidates = [
      result_payload.get("buildStatus"),
      result_payload.get("build_status"),
      result_payload.get("status"),
    ]
    normalized = {str(item).strip().lower() for item in success_values}
    return any(str(value).strip().lower() in normalized for value in candidates if value is not None)
