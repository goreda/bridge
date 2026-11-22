#!/bin/bash
# Fetch the pinned 3D models listed as `usable` in models/models.lock.tsv into a gor-owned folder.
# Every file is downloaded from a pinned revision and kept only if its sha256 matches the lock; a mismatch deletes it and fails.
# Rows that are not `usable` are never fetched. Weights are never committed. Folder: $GOR_MODELS_DIR or ~/Library/Application Support/gor/models.
# GOR_MODELS_MIRROR=/dir (test only) reads <repo>/<file> from a local directory instead of huggingface.co.
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"; lock="${GOR_MODELS_LOCK:-$here/models/models.lock.tsv}"
dest="${GOR_MODELS_DIR:-$HOME/Library/Application Support/gor/models}"; mkdir -p "$dest" || exit 2
sum() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1; else sha256sum "$1" | cut -d' ' -f1; fi; }
rc=0
# CoreML kit rows (id contains coreml-kit): the archive is a flat tar of *.mlpackage dirs plus kit_manifest.json. After its sha256 matches it is unpacked into $dest/kit,
# every package named in the archive's kit_manifest.json must be present, and $dest/kit/.installed-<id> records the archive sha. Rows whose repo is https://github.com/OWNER/REPO
# are release assets fetched with the owner's own `gh` login (no token is ever stored or passed by gor); anything else comes from huggingface.co.
install_kit() { # id archive sha
  local kd="$dest/kit" st="$dest/.kit-stage-$1"
  echo "verify kit $1: checking installed package hashes and sizes"
  if [ "$(cat "$kd/.installed-$1" 2>/dev/null)" = "$3" ] && /usr/bin/python3 "$here/tools/depth_analysis/kit_hash.py" --verify-archive "$1" "$kd" "$kd/kit_manifest.$1.json"; then return 0; fi
  echo "repair kit $1: re-unpacking the sha-verified archive"
  rm -f "$kd/.installed-$1" "$kd"/.verified-*
  rm -rf "$st"; mkdir -p "$st" "$kd" || return 1
  tar -xf "$2" -C "$st" 2>/dev/null || { echo "FAIL $1: kit archive did not unpack" >&2; rm -rf "$st"; return 1; }
  [ -f "$st/kit_manifest.json" ] || { echo "FAIL $1: kit_manifest.json missing in archive" >&2; rm -rf "$st"; return 1; }
  local pk; for pk in $(grep -o '"[A-Za-z0-9_.]*\.mlpackage"' "$st/kit_manifest.json" | tr -d '"' | sort -u); do
    case "$pk" in moge2_*) case "$1" in moge2*) ;; *) continue;; esac;; *) case "$1" in moge2*) continue;; esac;; esac   # each archive carries only its own packages
    [ -d "$st/$pk" ] || { echo "FAIL $1: package $pk missing in archive" >&2; rm -rf "$st"; return 1; }
    rm -rf "$kd/$pk"; mv "$st/$pk" "$kd/$pk" || { rm -rf "$st"; return 1; }
  done
  cp "$st/kit_manifest.json" "$kd/kit_manifest.json" 2>/dev/null; cp "$st/kit_manifest.json" "$kd/kit_manifest.$1.json" 2>/dev/null;   # per-archive copy: KitHash verifies each archive against its own filtered manifest
  /usr/bin/python3 "$here/tools/depth_analysis/kit_hash.py" --verify-archive "$1" "$kd" "$kd/kit_manifest.$1.json" || { echo "FAIL $1: unpacked package verification failed" >&2; rm -rf "$st"; return 1; }
  printf '%s' "$3" > "$kd/.installed-$1"; rm -rf "$st"; echo "kit  $1 installed"
}
# 190w W3: nunif weights kit (id contains nunif-weights-kit): a flat tar of .pth files unpacked into $dest/nunif (SynthMethod.present looks there by file name); marker .installed-<id> = archive sha.
install_nunif() { # id archive sha
  local nd="$dest/nunif" st="$dest/.nunif-stage-$1"
  [ "$(cat "$nd/.installed-$1" 2>/dev/null)" = "$3" ] && return 0
  rm -rf "$st"; mkdir -p "$st" "$nd" || return 1
  tar -xf "$2" -C "$st" 2>/dev/null || { echo "FAIL $1: archive did not unpack" >&2; rm -rf "$st"; return 1; }
  local f n=0; for f in $(cd "$st" && find . -type f | sed 's|^\./||'); do mkdir -p "$nd/$(dirname "$f")"; mv "$st/$f" "$nd/$f" || { rm -rf "$st"; return 1; }; n=$((n+1)); done
  [ "$n" -gt 0 ] || { echo "FAIL $1: archive is empty" >&2; rm -rf "$st"; return 1; }
  printf '%s' "$3" > "$nd/.installed-$1"; rm -rf "$st"; echo "nunif $1 installed ($n files)"
}
# 190w W3: nunif CoreML kit (id contains nunif-coreml, deliberately NOT "coreml-kit": it must not gate the 3D-ready state or share <models>/kit with the VDA/MoGe kits): the whole tar (4 fp16 mlpackages,
# fixtures, kit_manifest.json) is unpacked into $dest/nunif-coreml; every package named in its kit_manifest.json must be present; marker .installed-<id> = archive sha.
install_nunif_coreml() { # id archive sha
  local nd="$dest/nunif-coreml" st="$dest/.nunifc-stage-$1"
  [ "$(cat "$nd/.installed-$1" 2>/dev/null)" = "$3" ] && return 0
  rm -rf "$st"; mkdir -p "$st" || return 1
  tar -xf "$2" -C "$st" 2>/dev/null || { echo "FAIL $1: archive did not unpack" >&2; rm -rf "$st"; return 1; }
  [ -f "$st/kit_manifest.json" ] || { echo "FAIL $1: kit_manifest.json missing in archive" >&2; rm -rf "$st"; return 1; }
  local pk; for pk in $(grep -o '"[A-Za-z0-9_.]*\.mlpackage"' "$st/kit_manifest.json" | tr -d '"' | sort -u); do
    [ -d "$st/$pk" ] || { echo "FAIL $1: package $pk missing in archive" >&2; rm -rf "$st"; return 1; }
  done
  rm -rf "$nd"; mv "$st" "$nd" || { rm -rf "$st"; return 1; }
  printf '%s' "$3" > "$nd/.installed-$1"; echo "nunif-coreml $1 installed"
}
# Each real asset transfer carries its pinned byte count; cached files do not create fake download-rate measurements.
transfer() { GOR_STEP_BYTES="$bytes" GOR_STEP_LIMIT=1800 /usr/bin/python3 "$here/tools/gor_step.py" "download $id" "$@"; }
gh_bin() { command -v gh 2>/dev/null || { for g in /opt/homebrew/bin/gh /usr/local/bin/gh; do [ -x "$g" ] && { echo "$g"; return; }; done; return 1; }; }
while IFS=$'\t' read -r id status license repo rev file sha bytes use; do
  [ "$id" = id ] && continue
  case "$id" in *"${GOR_MODELS_ONLY:-}"*) ;; *) continue;; esac     # GOR_MODELS_ONLY=coreml-kit: only rows whose id contains it (the app needs just the kit)
  [ "$status" = usable ] || { echo "skip $id ($status)"; continue; }
  case "$license" in Apache-2.0|MIT) ;; *) echo "REFUSE $id: licence $license not allowed" >&2; rc=1; continue;; esac
  lrepo="${repo#https://}"; out="$dest/$lrepo/$file"; mkdir -p "$(dirname "$out")"
  if [ -f "$out" ] && [ "$(sum "$out")" = "$sha" ]; then
    case "$id" in *nunif-coreml*) install_nunif_coreml "$id" "$out" "$sha" || rc=1;; *coreml-kit*) install_kit "$id" "$out" "$sha" || rc=1;; *nunif-weights-kit*) install_nunif "$id" "$out" "$sha" || rc=1;; esac
    echo "ok   $id (cached)"; continue
  fi
  tmp="$out.part"; rm -f "$tmp"
  if [ -n "${GOR_MODELS_MIRROR:-}" ]; then cp "$GOR_MODELS_MIRROR/$lrepo/$file" "$tmp" 2>/dev/null || { echo "FAIL $id: mirror copy" >&2; rc=1; continue; }
  elif [ "${repo#https://github.com/}" != "$repo" ]; then
    slug="${repo#https://github.com/}"; got=0
    # Route 1: GitHub CLI when it is installed, signed in and can see the repo.
    if gh="$(gh_bin)" && "$gh" auth status >/dev/null 2>&1 && "$gh" api "repos/$slug" --silent >/dev/null 2>&1; then
      transfer "$gh" release download "$rev" -R "$slug" -p "$file" -O "$tmp" --clobber >/dev/null 2>&1 && got=1
    fi
    # Route 2 (no gh needed): the GitHub sign-in git already uses on this Mac (or GH_TOKEN / GITHUB_TOKEN) through the release API. The token is never printed or stored.
    if [ "$got" = 0 ]; then
      tok="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
      [ -n "$tok" ] || tok="$(printf 'protocol=https\nhost=github.com\n\n' | GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never GIT_ASKPASS=/usr/bin/true git credential fill 2>/dev/null | sed -n 's/^password=//p' | head -1)"
      if [ -n "$tok" ]; then
        aid="$(curl -fsS -m 30 -H "Authorization: token $tok" "https://api.github.com/repos/$slug/releases/tags/$rev" 2>/dev/null | python3 -c 'import sys,json; n=sys.argv[1]; print(next((str(a["id"]) for a in json.load(sys.stdin).get("assets",[]) if a.get("name")==n),""))' "$file" 2>/dev/null)"
        [ -n "$aid" ] && transfer curl -fL --retry 3 -sS -m 1800 -H "Authorization: token $tok" -H "Accept: application/octet-stream" -o "$tmp" "https://api.github.com/repos/$slug/releases/assets/$aid" 2>/dev/null && got=1
      fi
    fi
    if [ "$got" = 0 ]; then rm -f "$tmp"; echo "FAIL $id: needs a GitHub sign-in with access to $slug (run: gh auth login)" >&2; rc=1; continue; fi
  else transfer curl -fL --retry 3 -sS -o "$tmp" "https://huggingface.co/$repo/resolve/$rev/$file" || { echo "FAIL $id: download" >&2; rm -f "$tmp"; rc=1; continue; }; fi
  if [ "$(sum "$tmp")" = "$sha" ]; then mv "$tmp" "$out"; echo "ok   $id"; case "$id" in *nunif-coreml*) install_nunif_coreml "$id" "$out" "$sha" || rc=1;; *coreml-kit*) install_kit "$id" "$out" "$sha" || rc=1;; *nunif-weights-kit*) install_nunif "$id" "$out" "$sha" || rc=1;; esac; else rm -f "$tmp"; echo "FAIL $id: sha256 mismatch, file removed" >&2; rc=1; fi
done < "$lock"
exit $rc
