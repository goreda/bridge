"""Compatibility entry point for the stable shipped architecture gate."""
import runpy
from pathlib import Path
runpy.run_path(str(Path(__file__).resolve().parents[1] / 'tools/architecture.py'), run_name='__main__')
