#!/usr/bin/env bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
hooks=$(git rev-parse --git-path hooks)
mkdir -p "$hooks"
if [ -e "$hooks/pre-push" ] && ! grep -q 'GOR_IDENTITY_GUARD' "$hooks/pre-push"; then
  echo 'Existing pre-push hook requires explicit composition; refusing overwrite' >&2; exit 2
fi
cp "$root/tools/check-identity.sh" "$hooks/check-identity.sh"
cat > "$hooks/pre-push" <<'HOOK'
#!/usr/bin/env bash
# GOR_IDENTITY_GUARD, installed from the tracked identity tool.
set -euo pipefail
exec bash "$(git rev-parse --git-path hooks)/check-identity.sh" "$@"
HOOK
chmod +x "$hooks/pre-push" "$hooks/check-identity.sh"
printf 'Installed identity pre-push guard in %s\n' "$hooks"
