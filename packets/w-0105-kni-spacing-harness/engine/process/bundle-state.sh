#!/usr/bin/env bash
# Five-minute KNI process bundle. Invoke from a verified task schedule.
# No execution of engine code or secret retrieval. Fail closed on upstream state.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
cd "$root"
branch=engine/kernel-envelope-20261010
if [ "$(git branch --show-current)" != "$branch" ]; then
  printf '%s\n' 'BLOCKED: unexpected branch' >&2
  exit 1
fi
# Scope exactly the authored process paths; do not stage unknown upstream files.
git add -- docs/engine/contracts engine/core engine/process
if ! git diff --cached --quiet; then
  git diff --cached --check
  git -c user.name='KNI local development' -c user.email='kni-local@localhost' \
    commit -m 'Bundle current KNI code contracts and open process state'
fi
printf 'LOCAL_HEAD=%s\n' "$(git rev-parse HEAD)"
base=$(git config --get kni.verifiedUpstreamBase || true)
remote=$(git remote get-url origin 2>/dev/null || true)
if [ -z "$base" ] || [ -z "$remote" ]; then
  printf '%s\n' 'PUSH_BLOCKED: UNVERIFIED-UPSTREAM-PLACEHOLDER or no authenticated remote'
  exit 2
fi
# Marker is operational metadata, not proof. Require actual verified-base ancestry.
if ! git merge-base --is-ancestor "$base" HEAD; then
  printf '%s\n' 'PUSH_BLOCKED: verified upstream base not in ancestry' >&2
  exit 2
fi
if [ "$remote" != 'https://github.com/goreda/kni.git' ] && [ "$remote" != 'git@github.com:goreda/kni.git' ]; then
  printf '%s\n' 'PUSH_BLOCKED: remote is not the authorized repository' >&2
  exit 2
fi
# Credential provisioning and upstream reconciliation happen separately.
# Normal non-force push only; failure is not retried or reported as success.
git push origin "HEAD:refs/heads/$branch"
local_head=$(git rev-parse HEAD)
remote_head=$(git ls-remote origin "refs/heads/$branch" | cut -f1)
if [ "$local_head" != "$remote_head" ]; then
  printf '%s\n' 'PUSH_UNVERIFIED: remote branch does not match local HEAD' >&2
  exit 3
fi
printf 'PUSH_VERIFIED=%s\n' "$remote_head"
