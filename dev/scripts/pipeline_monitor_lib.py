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

TERMINAL_STATUSES = {
    "cancelled",
    "pushed",
    "completed",
    "build_failed",
    "agent_exited_without_result",
    "dry_run_success_detected",
}


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


def freeze_cancelled_inspection(state: dict[str, Any]) -> dict[str, Any]:
    inspection = state.get("inspection") or {}
    cancelled_at = state.get("cancelled_at") or state.get("runtime_ended_at") or now_local_iso()
    inspection["status"] = "cancelled"
    inspection["message"] = "任务已取消，停止巡检"
    inspection.setdefault("last_checked_at", cancelled_at)
    inspection.setdefault("cycle_count", int(inspection.get("cycle_count") or 0))
    state["inspection"] = inspection
    state["status"] = "cancelled"
    state["cancelled_at"] = cancelled_at
    state["runtime_ended_at"] = state.get("runtime_ended_at") or cancelled_at
    return state


def persist_state(
    state_file: Path,
    state: dict[str, Any],
    logger: logging.Logger,
) -> None:
    latest = load_runtime_state(state_file)
    if latest:
        if latest.get("web") and not state.get("web"):
            state["web"] = latest["web"]
        if latest.get("result_payload") and not state.get("result_payload"):
            state["result_payload"] = latest["result_payload"]
        if latest.get("status") == "cancelled":
            latest = freeze_cancelled_inspection(latest)
            latest.setdefault("web", state.get("web") or {})
            if state.get("web"):
                latest["web"] = state["web"]
            if state.get("result_payload") and not latest.get("result_payload"):
                latest["result_payload"] = state["result_payload"]
            state = latest
    update_runtime_state(state_file, state, logger)


def should_stop(state: dict[str, Any], stop_event: threading.Event | None) -> bool:
    if state.get("status") == "cancelled":
        return True
    if stop_event and stop_event.is_set():
        return True
    return False


def handle_state_file(
    repo_root: Path,
    config: dict[str, Any],
    state_file: Path,
    logger: logging.Logger,
    dry_run: bool,
    stop_event: threading.Event | None = None,
) -> None:
    state = load_runtime_state(state_file)
    if not state:
        logger.warning("未找到状态文件: %s", state_file)
        return

    state = initialize_inspection(state)
    if should_stop(state, stop_event):
        if state.get("status") == "cancelled":
            persist_state(state_file, freeze_cancelled_inspection(state), logger)
        return

    result_json = Path(state["result_json"])
    pid = state.get("agent", {}).get("pid")
    logger.info("开始巡检任务: %s", state.get("scenario_branch"))

    if state.get("status") == "dry_run":
        state["runtime_ended_at"] = state.get("runtime_ended_at") or now_local_iso()
        update_inspection_state(state, status="done", message="dry-run 模式，未实际下发 Agent")
        persist_state(state_file, state, logger)
        return

    if result_json.exists():
        if should_stop(state, stop_event):
            persist_state(state_file, freeze_cancelled_inspection(state), logger)
            return

        result_payload = read_json(result_json)
        success = detect_build_success(result_payload, config["scheduler"]["success_values"])
        state["result_payload"] = result_payload

        if success:
            if state.get("status") == "pushed":
                update_inspection_state(state, status="done", message="结果已提交并推送")
                persist_state(state_file, state, logger)
                return

            logger.info("检测到成功结果，准备提交并推送")
            update_inspection_state(state, status="running", message="检测到成功结果，准备自动提交")
            persist_state(state_file, state, logger)

            latest = load_runtime_state(state_file) or state
            if should_stop(latest, stop_event):
                persist_state(state_file, freeze_cancelled_inspection(latest), logger)
                return

            commit_and_push(repo_root, config, latest, logger, dry_run)

            latest = load_runtime_state(state_file) or latest
            if should_stop(latest, stop_event):
                persist_state(state_file, freeze_cancelled_inspection(latest), logger)
                return

            latest["status"] = "pushed" if not dry_run else "dry_run_success_detected"
            latest["pushed_at"] = now_local_iso()
            latest["runtime_ended_at"] = latest["pushed_at"]
            update_inspection_state(
                latest,
                status="done",
                message="结果已推送" if not dry_run else "dry-run 模式，检测到成功结果",
            )
            persist_state(state_file, latest, logger)
            return

        logger.warning("结果 JSON 已生成，但 build 未成功")
        state["status"] = "build_failed"
        state["runtime_ended_at"] = now_local_iso()
        update_inspection_state(state, status="failed", message="构建失败，请检查结果输出")
        persist_state(state_file, state, logger)
        return

    if is_process_running(pid):
        if should_stop(state, stop_event):
            persist_state(state_file, freeze_cancelled_inspection(state), logger)
            return
        state["status"] = "inspection_running"
        update_inspection_state(state, status="running", message="Agent 运行中，等待结果输出")
        persist_state(state_file, state, logger)
        return

    logger.warning("Agent 已退出，但未发现结果 JSON")
    state["status"] = "agent_exited_without_result"
    state["runtime_ended_at"] = now_local_iso()
    update_inspection_state(state, status="failed", message="Agent 已退出，未产出结果")
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
    logger.info("开始巡检循环，每 %s 秒检查一次，最多 %s 轮", interval, max_cycles)

    for index in range(max_cycles):
        if stop_event and stop_event.is_set():
            logger.info("收到停止信号，退出巡检循环")
            return

        logger.info("巡检轮次: %s/%s", index + 1, max_cycles)
        state_files = collect_state_files(repo_root, config, state_arg)
        if not state_files:
            logger.info("未检测到待巡检的状态文件")

        for state_file in state_files:
            current = load_runtime_state(state_file)
            if current and current.get("status") == "cancelled":
                logger.info("检测到任务已取消，停止巡检: %s", state_file)
                return
            if stop_event and stop_event.is_set():
                logger.info("收到停止信号，结束当前巡检")
                return

            handle_state_file(repo_root, config, state_file, logger, dry_run, stop_event)

            current = load_runtime_state(state_file)
            if current and current.get("status") == "cancelled":
                logger.info("状态文件已进入取消态，停止后续巡检: %s", state_file)
                return

        if index < max_cycles - 1:
            if stop_event and stop_event.wait(interval):
                logger.info("巡检等待被中断，退出")
                return
            if not stop_event:
                time.sleep(interval)
