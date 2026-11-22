#!/usr/bin/env python3
"""192d pupil distance replaces ideal face-box pitch model."""
from pathlib import Path
import runpy
root=Path(__file__).resolve().parents[2]
runpy.run_path(str(root/"Tests/HeadPose/pipeline192d_test.py"),run_name="__main__")
