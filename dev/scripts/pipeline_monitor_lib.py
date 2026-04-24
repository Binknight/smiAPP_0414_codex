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
    setup_stream_logger,
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


def get_global_logs_root(repo_root: Path) -> Path:
    return ensure_dir(repo_root / "dev" / "logs")


def prepare_logger(repo_root: Path, config: dict[str, Any], suffix: str) -> logging.Logger:
    logs_root = get_global_logs_root(repo_root)
    log_file = logs_root / f"monitor-{sanitize_name(suffix)}.log"
    return setup_logger("dev-monitor", log_file)


def get_pipeline_logger(state: dict[str, Any] | None, fallback_name: str) -> logging.Logger:
    if state:
        log_file = state.get("log_file")
        if log_file:
            logger_key = sanitize_name(str(state.get("pipeline_key") or state.get("scenario_key") or Path(str(log_file)).stem))
            return setup_logger(f"pipeline-monitor-{logger_key}", Path(str(log_file)))
    return setup_stream_logger(fallback_name)


def collect_state_files(repo_root: Path, config: dict[str, Any], state_arg: str | None) -> list[Path]:
    if state_arg:
        return [resolve_path(repo_root, state_arg)]
    scenarios_root = ensure_dir(resolve_path(repo_root, config["paths"]["scenarios_root"]))
    return sorted(scenarios_root.glob("*/state/*.json"))


def build_include_paths(repo_root: Path, state: dict[str, Any], config: dict[str, Any], logger: logging.Logger) -> list[str]:
    include_paths: list[str] = []
    pipeline_root = state.get("pipeline_root")
    if pipeline_root:
        root_path = Path(str(pipeline_root))
        try:
            include_paths.append(str(root_path.relative_to(repo_root)))
        except ValueError:
            logger.warning("Pipeline root is outside repo root, skip auto-include: %s", root_path)

    scenario_input = state.get("scenario_input")
    if scenario_input:
        input_path = Path(str(scenario_input))
        try:
            include_paths.append(str(input_path.relative_to(repo_root)))
        except ValueError:
            logger.warning("Scenario input is outside repo root, skip auto-include: %s", input_path)

    include_paths.extend(config.get("commit", {}).get("shared_include_paths", []))
    return list(dict.fromkeys(include_paths))


def commit_and_push(
    repo_root: Path,
    config: dict[str, Any],
    state: dict[str, Any],
    logger: logging.Logger,
    dry_run: bool,
) -> None:
    scheduler_config = config["scheduler"]
    remote_name = config["git"]["remote_name"]
    include_paths = build_include_paths(repo_root, state, config, logger)
    branch_name = state.get("branch_name") or state.get("base_branch") or state.get("scenario_branch")
    commit_message = scheduler_config["commit_message_template"].format(
        pipeline_key=state.get("pipeline_key") or state.get("scenario_key"),
        scenario_id=state.get("scenario_id"),
        app_type=state.get("app_type"),
        scenario_branch=branch_name,
    )

    if not include_paths:
        logger.info("No whitelisted paths resolved, skip commit.")
        return

    logger.info("Preparing commit for whitelisted paths: %s", ", ".join(include_paths))
    if dry_run:
        logger.info("dry-run mode, skip git add/commit/push.")
        return

    run_command(["git", "checkout", branch_name], repo_root, logger)
    run_command(["git", "add", "--", *include_paths], repo_root, logger)

    status_result = run_command(["git", "status", "--short"], repo_root, logger, check=False)
    if not status_result.stdout.strip():
        logger.info("No staged changes detected, skip commit.")
    else:
        run_command(["git", "commit", "-m", commit_message], repo_root, logger)

    run_command(["git", "push", "-u", remote_name, branch_name], repo_root, logger)


def initialize_inspection(state: dict[str, Any]) -> dict[str, Any]:
    inspection = state.get("inspection") or {}
    inspection.setdefault("status", "pending")
    inspection.setdefault("last_checked_at", None)
    inspection.setdefault("cycle_count", 0)
    inspection.setdefault("message", "Waiting for inspection")
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
    inspection["message"] = "Task cancelled, stop inspection"
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
        logger.warning("State file not found: %s", state_file)
        return

    logger = get_pipeline_logger(state, f"pipeline-monitor-{sanitize_name(state_file.stem)}")
    state = initialize_inspection(state)
    if should_stop(state, stop_event):
        if state.get("status") == "cancelled":
            persist_state(state_file, freeze_cancelled_inspection(state), logger)
        return

    result_json = Path(state["result_json"])
    pid = state.get("agent", {}).get("pid")
    logger.info("Start inspection for pipeline: %s", state.get("pipeline_key") or state.get("scenario_key"))

    if state.get("status") == "dry_run":
        state["runtime_ended_at"] = state.get("runtime_ended_at") or now_local_iso()
        update_inspection_state(state, status="done", message="dry-run mode, agent not dispatched")
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
                update_inspection_state(state, status="done", message="Result already committed and pushed")
                persist_state(state_file, state, logger)
                return

            logger.info("Successful result detected, prepare commit and push")
            update_inspection_state(state, status="running", message="Successful result detected, preparing auto-commit")
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
                message="Result pushed" if not dry_run else "dry-run mode, successful result detected",
            )
            persist_state(state_file, latest, logger)
            return

        logger.warning("Result JSON exists but build is not successful")
        state["status"] = "build_failed"
        state["runtime_ended_at"] = now_local_iso()
        update_inspection_state(state, status="failed", message="Build failed, check result payload")
        persist_state(state_file, state, logger)
        return

    if is_process_running(pid):
        if should_stop(state, stop_event):
            persist_state(state_file, freeze_cancelled_inspection(state), logger)
            return
        state["status"] = "inspection_running"
        update_inspection_state(state, status="running", message="Agent still running, waiting for result")
        persist_state(state_file, state, logger)
        return

    logger.warning("Agent exited but result JSON was not found")
    state["status"] = "agent_exited_without_result"
    state["runtime_ended_at"] = now_local_iso()
    update_inspection_state(state, status="failed", message="Agent exited without result output")
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
    logger.info("Start inspection loop: interval=%s seconds, max_cycles=%s", interval, max_cycles)

    for index in range(max_cycles):
        if stop_event and stop_event.is_set():
            logger.info("Stop signal received, exit inspection loop")
            return

        logger.info("Inspection cycle: %s/%s", index + 1, max_cycles)
        state_files = collect_state_files(repo_root, config, state_arg)
        if not state_files:
            logger.info("No state files found for inspection")

        for state_file in state_files:
            current = load_runtime_state(state_file)
            state_logger = get_pipeline_logger(current, f"pipeline-monitor-{sanitize_name(state_file.stem)}") if current else logger
            if current and current.get("status") == "cancelled":
                state_logger.info("Task already cancelled, stop inspection: %s", state_file)
                return
            if stop_event and stop_event.is_set():
                state_logger.info("Stop signal received, abort current inspection")
                return

            state_logger.info("Processing inspection state file: %s", state_file)
            handle_state_file(repo_root, config, state_file, logger, dry_run, stop_event)

            current = load_runtime_state(state_file)
            state_logger = get_pipeline_logger(current, f"pipeline-monitor-{sanitize_name(state_file.stem)}") if current else logger
            if current and current.get("status") == "cancelled":
                state_logger.info("State moved to cancelled, stop further inspection: %s", state_file)
                return

        if index < max_cycles - 1:
            if stop_event and stop_event.wait(interval):
                logger.info("Inspection wait interrupted, exit loop")
                return
            if not stop_event:
                time.sleep(interval)
