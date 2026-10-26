#!/bin/sh
# Packaging only. Never runs engine/build/tests and never pushes.
set -eu
repo=$(git rev-parse --show-toplevel)
head=$(git rev-parse HEAD)
output=${1:?Supply an archive destination explicitly}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
git -C "$repo" archive "$head" | tar -x -C "$work"
mkdir -p "$work/docs/engine/contracts"
{
  printf '%s\n' '# Local snapshot provenance' '' "Source tree HEAD: $head" 'Base: UNVERIFIED-UPSTREAM-PLACEHOLDER' 'Relay snapshot does not preserve local ancestry.' 'All build/tests/engine generation/parser/render/native validation NOT_RUN.' '' 'Ordered local commits:'
  git -C "$repo" log --reverse --format='%H %s' "$head"
} > "$work/docs/engine/contracts/LOCAL-SNAPSHOT-PROVENANCE.md"
tar -czf "$output" -C "$work" .
sha256sum "$output"
# Artifact-derived delivery evidence, never estimate counts from memory.
files=$(tar -tzf "$output" | awk '!/\/$/{n++}END{print n+0}')
manifest=$(tar -xOzf "$output" ./docs/engine/contracts/LOCAL-SNAPSHOT-PROVENANCE.md)
commits=$(printf '%s\n' "$manifest" | awk 'length($1)==40 && $1 !~ /[^0-9a-f]/{n++}END{print n+0}')
artifact_head=$(printf '%s\n' "$manifest" | sed -n 's/^Source tree HEAD: //p')
[ "$artifact_head" = "$head" ] || { printf '%s\n' 'Artifact HEAD mismatch' >&2; exit 1; }
printf 'artifact_files=%s\nmanifest_commits=%s\nartifact_head=%s\n' "$files" "$commits" "$artifact_head"
