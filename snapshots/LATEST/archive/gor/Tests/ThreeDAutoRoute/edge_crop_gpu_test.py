#!/usr/bin/env python3
"""192c supersedes192b black support strips: one common crop, only physical gutter."""
from pathlib import Path
p=Path(__file__).with_name('common_window_gpu_test.py')
exec(compile(p.read_text(),str(p),'exec'),{'__file__':str(p),'__name__':'__main__'})
