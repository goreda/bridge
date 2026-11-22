#!/usr/bin/env python3
"""Bounded secret-pattern check over payload files; no external service."""
from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
patterns = [r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
            r'\bAKIA[A-Z0-9]{16}\b', r'\bgh[pousr]_[A-Za-z0-9]{30,}\b',
            r'\bsk-[A-Za-z0-9]{32,}\b',
            r'(?im)^\s*(?:password|api_key|access_token|secret_key)\s*[:=]\s*[\x22\x27]?[A-Za-z0-9/+_-]{12,}']
issues = []
files = [p for p in root.rglob('*') if p.is_file() and '.build' not in p.parts and p.name != 'SHA256SUMS']
for path in files:
    text = path.read_text()
    for pattern in patterns:
        if re.search(pattern, text): issues.append(str(path.relative_to(root)))
if issues: raise SystemExit('scan matches: '+str(issues))
print('secret scan: clean')
print('bounded scan files:', len(files))
