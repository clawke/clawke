#!/usr/bin/env python3
"""Launch Clawke channel for Hermes.

This script starts the Clawke gateway channel that connects Hermes AIAgent
to the Clawke Server via WebSocket. It runs inside the same Python environment
as hermes-agent.

Usage:
    python3 run.py                              # Use defaults
    CLAWKE_WS_URL=ws://server:8766 python3 run.py  # Custom server URL

Requirements:
    - hermes-agent must be importable (installed or on sys.path)
    - websockets >= 12.0
"""

from __future__ import annotations

import asyncio
import logging
import os
import sys
from pathlib import Path


def _setup_hermes_path() -> None:
    """Ensure hermes-agent is on sys.path.

    Checks common installation locations:
    1. Already importable (pip installed or PYTHONPATH set)
    2. ~/.hermes/hermes-agent/
    3. Adjacent to this script's parent directories
    """
    try:
        import run_agent  # noqa: F401
        return  # Already importable
    except ImportError:
        pass

    # Try ~/.hermes/hermes-agent/
    hermes_dir = Path.home() / ".hermes" / "hermes-agent"
    if hermes_dir.is_dir():
        sys.path.insert(0, str(hermes_dir))
        return

    # Try ../../hermes-agent relative to this script
    script_dir = Path(__file__).resolve().parent
    for ancestor in [script_dir.parent.parent, script_dir.parent.parent.parent]:
        candidate = ancestor / "hermes-agent"
        if candidate.is_dir():
            sys.path.insert(0, str(candidate))
            return


def main() -> None:
    """Entry point."""
    # Setup logging — console + file
    log_dir = Path.home() / ".clawke" / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
        datefmt="%H:%M:%S",
        handlers=[
            logging.StreamHandler(),
            logging.FileHandler(log_dir / "hermes-gateway.log"),
        ],
    )

    # Ensure hermes-agent is importable
    _setup_hermes_path()

    # Verify AIAgent is available
    try:
        from run_agent import AIAgent  # noqa: F401
        logging.getLogger("clawke.hermes").info("✓ AIAgent imported successfully")
    except ImportError as e:
        print(f"\n❌ Cannot import hermes-agent: {e}")
        print("\nMake sure hermes-agent is installed or on PYTHONPATH:")
        print("  pip install hermes-agent")
        print("  or: export PYTHONPATH=/path/to/hermes-agent:$PYTHONPATH")
        sys.exit(1)

    from config import load_config
    from clawke_channel import ClawkeHermesGateway

    config = load_config()
    gateway = ClawkeHermesGateway(config)

    print(f"\n🔗 Clawke Hermes Gateway")
    print(f"   Server:  {config.ws_url}")
    print(f"   Account: {config.account_id}")
    if config.model:
        print(f"   Model:   {config.model}")
    if config.provider:
        print(f"   Provider: {config.provider}")
    print()

    try:
        asyncio.run(gateway.start())
    except KeyboardInterrupt:
        print("\n👋 Gateway stopped")


if __name__ == "__main__":
    main()
