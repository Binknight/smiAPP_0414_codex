from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any

from common import configure_stdio, read_json, resolve_path
from pipeline_monitor_lib import collect_state_files, handle_state_file, prepare_logger, run_loop


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
        run_loop(repo_root, config, args.state, logger, args.dry_run)
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
