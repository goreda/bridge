#!/usr/bin/env bash
# Check the outgoing commit set, never rewrite identities or push on success.
set -euo pipefail
want='338160556+zuellue@users.noreply.github.com'
check_set() {
    local sha author committer bad=0
    while IFS= read -r sha; do
        [ -n "$sha" ] || continue
        author=$(git show -s --format=%ae "$sha")
        committer=$(git show -s --format=%ce "$sha")
        if [ "$author" != "$want" ] || [ "$committer" != "$want" ]; then
            printf 'IDENTITY REFUSAL %s author=%s committer=%s\n' "$sha" "$author" "$committer" >&2
            bad=1
        fi
    done
    [ "$bad" -eq 0 ]
}
if [ "${1:-}" = '--range' ]; then
    [ "$#" -eq 3 ] || { echo 'usage: check-identity.sh --range OLD NEW' >&2; exit 2; }
    git cat-file -e "$2^{commit}" && git cat-file -e "$3^{commit}" || exit 2
    commits=$(git rev-list "$3" "^$2") || exit 2
    check_set <<< "$commits"
    exit
fi
remote=${1:-origin}
zero=0000000000000000000000000000000000000000
while read -r local_ref local_oid remote_ref remote_oid; do
    [ "$local_oid" != "$zero" ] || continue
    git cat-file -e "$local_oid^{commit}" || { echo 'Cannot resolve outgoing commit' >&2; exit 2; }
    if [ "$remote_oid" != "$zero" ]; then
        git cat-file -e "$remote_oid^{commit}" || { echo 'Fetch remote boundary before push' >&2; exit 2; }
        commits=$(git rev-list "$local_oid" "^$remote_oid") || exit 2
    else
        # New branch: exclude all live remote-reachable history, not stale local refs.
        refs=$(git ls-remote --heads --tags "$remote") || exit 2
        args=("$local_oid")
        while read -r oid ref; do
            [ -n "$oid" ] || continue
            git cat-file -e "$oid" || { echo 'Fetch remote refs before creating branch; boundary unavailable' >&2; exit 2; }
            if git rev-parse --verify -q "$oid^{commit}" >/dev/null; then args+=("^$oid"); fi
        done <<< "$refs"
        commits=$(git rev-list "${args[@]}") || exit 2
    fi
    check_set <<< "$commits" || exit 1
done
