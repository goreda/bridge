#!/bin/sh
# Install with: git config core.hooksPath archive/gor/tools/git-hooks
# Verify every outgoing commit from Git's pre-push stdin, not just HEAD.
set -eu
top=$(git rev-parse --show-toplevel)
exec python3 "$top/archive/gor/tools/verify-push-delivery.py"
