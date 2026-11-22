#!/usr/bin/env python3
"""Kit download must not depend on the gh CLI (owner Mac capture 261109-152855: kit_missing). tools/gor-fetch-models.sh tries gh, then the GitHub sign-in git already uses / GH_TOKEN
through the release API, and on failure prints ONE plain need. Pinned as text (the real download was run once by hand with a token: sha-verified install of a 19.8 MB kit asset)."""
import pathlib, subprocess, sys
r = pathlib.Path(__file__).resolve().parents[2]
s = (r / 'tools/gor-fetch-models.sh').read_text()
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
check('script parses', subprocess.run(['bash', '-n', str(r / 'tools/gor-fetch-models.sh')]).returncode == 0)
check('route 1: gh when installed, signed in and with access', '"$gh" release download "$rev" -R "$slug"' in s and '"$gh" auth status' in s)
check('route 2: git credential / GH_TOKEN through the release API, no gh needed', 'git credential fill' in s and 'GH_TOKEN' in s and 'releases/assets/$aid' in s and 'Accept: application/octet-stream' in s)
check('token never printed', 'echo "$tok"' not in s and 'printf \'%s\' "$tok"' not in s)
check('one plain failure line naming the single need', 'FAIL $id: needs a GitHub sign-in with access to $slug (run: gh auth login)' in s)
check('sha256 verification untouched', '[ "$(sum "$tmp")" = "$sha" ]' in s)
print('fetch routes: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
