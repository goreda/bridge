#!/usr/bin/env python3
"""192d fixed follow replaces pre192d mode-switch latency gate."""
from pathlib import Path
import runpy
root=Path(__file__).resolve().parents[2]
runpy.run_path(str(root/"Tests/HeadPose/pipeline192d_test.py"),run_name="__main__")
