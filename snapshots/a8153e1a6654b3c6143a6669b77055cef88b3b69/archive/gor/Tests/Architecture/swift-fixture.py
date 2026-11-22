#!/usr/bin/env python3
"""Supplementary graph replay for gate fixtures only. Never a Swift compile."""
import json
from pathlib import Path
import re
import sys
root = Path(sys.argv[sys.argv.index('--package-path') + 1])
source = (root / 'Package.swift').read_text()
if 'GorStereo' in source and 'GorFit' in source:
    print(json.dumps({'targets': [{'name': 'GorStereo', 'type': 'regular', 'dependencies': [{'byName': ['GorFit', None]}]}, {'name': 'GorFit', 'type': 'regular', 'dependencies': []}]}))
else:
    print((Path(__file__).with_name('package-gor.json')).read_text())
