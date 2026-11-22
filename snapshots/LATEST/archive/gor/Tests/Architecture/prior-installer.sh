# Source:281910e8c779862216b8a0457481c1f531b18042 archive/gor/build.sh
# Exact extracted installer functions, supplementary Ubuntu execution fixture.
gor_install_tree() {
    local src="$1" label="$2" rel rb_dir pf enum_dir enum_rc=0 op
    local it_changed=() it_added=() it_deleted=() ops=()
    [ -d "$src" ] || { echo "      source tree missing at $src; nothing changed." >&2; exit 1; }
    [ -d "$src/Sources" ] || { echo "      source tree at $src has no Sources/; nothing changed." >&2; exit 1; }
    [ -d "$project_root/Sources" ] || { echo "      project root has no Sources/; nothing changed." >&2; exit 1; }
    # Enumerate both trees with error-checked finds BEFORE any mutation, so a
    # decline, a missing tty, or an enumeration failure leaves the project
    # byte-identical. Only operands that exist are enumerated (build.sh or
    # Resources may be absent in a legitimate tree shape); any real find error
    # fails closed instead of silently producing a partial list.
    enum_dir=$(mktemp -d /tmp/gor-install-enum.XXXXXX) || { echo "      cannot enumerate trees; nothing changed." >&2; exit 1; }
    for op in Sources Package.swift build.sh gor-capture-channel.py Tests Resources; do [ -e "$project_root/$op" ] && ops+=("$op"); done
    if [ ${#ops[@]} -eq 0 ]; then echo "      project tree is empty; nothing changed." >&2; rm -rf "$enum_dir"; exit 1; fi
    ( cd "$project_root" && find "${ops[@]}" -type f ) > "$enum_dir/proj.txt" 2>"$enum_dir/proj.err" || enum_rc=1
    ops=()
    for op in Sources Package.swift build.sh gor-capture-channel.py Tests Resources; do [ -e "$src/$op" ] && ops+=("$op"); done
    ( cd "$src" && find "${ops[@]}" -type f ) > "$enum_dir/src.txt" 2>"$enum_dir/src.err" || enum_rc=1
    if [ "$enum_rc" != 0 ] || [ -s "$enum_dir/proj.err" ] || [ -s "$enum_dir/src.err" ]; then
        echo "      source enumeration failed; nothing changed." >&2
        rm -rf "$enum_dir"; exit 1
    fi
    while IFS= read -r rel; do
        if [ -f "$project_root/$rel" ]; then
            cmp -s "$src/$rel" "$project_root/$rel" || it_changed+=("$rel")
        else
            it_added+=("$rel")
        fi
    done < "$enum_dir/src.txt"
    # 176c-fix: the delivered tree is a code-only OVERLAY, never an
    # authoritative full tree: vendor models under Resources/ are too large to
    # be captured to the branch, so they can never appear in src - and any
    # project file absent from src must NOT be classified as deleted. The
    # deletion class is disabled entirely; a future delivery that needs a file
    # removed must carry an explicit removal list (none does today).
    # Owner's explicit Nov1 consolidation: retire ONLY these two known logger
    # sources when the complete combined replacement is present. Overlay
    # omissions still NEVER imply deletion. Unknown local edits fail closed.
    if [ -f "$src/Sources/gor/Diag.swift" ]; then
        if grep -q '^enum ThreadCpuDiag {' "$src/Sources/gor/Diag.swift" &&
           grep -q '^enum MainThreadDiag {' "$src/Sources/gor/Diag.swift"; then
            local old_diag expected_diag actual_diag
            for old_diag in ThreadCpuDiag MainThreadDiag; do
                rel="Sources/gor/$old_diag.swift"
                [ ! -f "$src/$rel" ] || { echo "diag consolidation: duplicate delivered source $rel" >&2; exit 1; }
                [ -e "$project_root/$rel" ] || continue
                [ -f "$project_root/$rel" ] && [ ! -L "$project_root/$rel" ] || { echo "diag consolidation: unexpected local file $rel" >&2; exit 1; }
                case "$old_diag" in
                    ThreadCpuDiag) expected_diag=aebe13945e48180d0e2c9554b7a342bfbaa421a92a57286ea530aa9c11a6db46 ;;
                    MainThreadDiag) expected_diag=0596077bd76cd8341999fa60eff4185b5ed112bb849d073fa76a0630a3a8e2c9 ;;
                esac
                actual_diag=$(shasum -a 256 "$project_root/$rel") || exit 1
                actual_diag=${actual_diag%% *}
                [ "$actual_diag" = "$expected_diag" ] || { echo "diag consolidation: local edits in $rel; nothing changed" >&2; exit 1; }
                it_deleted+=("$rel")
            done
        fi
    fi
    rm -rf "$enum_dir"
    # ALL confirmations run here, BEFORE the backup and any project mutation:
    # one prompt per big file the install will overwrite or delete. Lists are
    # arrays, so the prompt's stdin is the real terminal, not a list file.
    for rel in ${it_changed[@]+"${it_changed[@]}"} ${it_deleted[@]+"${it_deleted[@]}"}; do
        [ -f "$project_root/$rel" ] || continue
        pf=$(stat -f%z "$project_root/$rel" 2>/dev/null || stat -c %s "$project_root/$rel" 2>/dev/null || echo 0)
        case "$pf" in ''|*[!0-9]*) pf=0 ;; esac
        if [ "$pf" -gt "$big_file_bytes" ]; then gor_big_file_confirm "$rel"; fi
    done
    # Mutation point. Backup first (shipped changes.txt kinds so --rollback can
    # undo it), then apply.
    rb_dir="$backups_dir/$(date +%y%m%d-%H%M%S)-pre-$label"
    # 174c: one timestamp name; a same-second collision stops loudly.
    [ -e "$rb_dir" ] && { echo "exists: $rb_dir — stopping, nothing moved" >&2; exit 1; }
    mkdir -p "$rb_dir" || exit 1
    : > "$rb_dir/changes.txt"
    for rel in ${it_changed[@]+"${it_changed[@]}"} ${it_deleted[@]+"${it_deleted[@]}"}; do
        mkdir -p "$rb_dir/$(dirname "$rel")"
        cp -p "$project_root/$rel" "$rb_dir/$rel" || { echo "      source backup: cp failed for $rel" >&2; exit 1; }
    done
    for rel in ${it_changed[@]+"${it_changed[@]}"}; do printf 'changed\t%s\n' "$rel" >> "$rb_dir/changes.txt"; done
    for rel in ${it_added[@]+"${it_added[@]}"};   do printf 'added\t%s\n'   "$rel" >> "$rb_dir/changes.txt"; done
    for rel in ${it_deleted[@]+"${it_deleted[@]}"}; do printf 'deleted\t%s\n' "$rel" >> "$rb_dir/changes.txt"; done
    if [ "$label" = diag-consolidation ] && [ "${#it_deleted[@]}" -gt 0 ]; then
        # The previous overlay already added this file. Undo of THIS migration
        # must park it too when it restores the two original enum definitions.
        printf 'added\tSources/gor/Diag.swift\n' >> "$rb_dir/changes.txt"
    fi
    gor_install_selftest_fixtures "$src" "$rb_dir"
    # The pinned entry-point file ships outside the capture find set (the Mac's
    # capture/push gates never see it); back it up when the install changes it.
    if [ -f "$project_root/gor-selftest.sh" ] && [ -f "$src/gor-selftest.sh" ] && ! cmp -s "$project_root/gor-selftest.sh" "$src/gor-selftest.sh"; then
        cp -p "$project_root/gor-selftest.sh" "$rb_dir/gor-selftest.sh" || { echo "      source backup: cp failed for gor-selftest.sh" >&2; exit 1; }
        printf 'changed\t%s\n' "gor-selftest.sh" >> "$rb_dir/changes.txt"
    fi
    echo "      source backup: $rb_dir ($label)"
    # Apply: per-file .tmp+mv (the snapshot re-exec guard covers build.sh itself).
    for rel in ${it_changed[@]+"${it_changed[@]}"} ${it_added[@]+"${it_added[@]}"}; do
        mkdir -p "$project_root/$(dirname "$rel")"
        cp -p "$src/$rel" "$project_root/$rel.tmp" && mv "$project_root/$rel.tmp" "$project_root/$rel" || { echo "      install: copy failed for $rel" >&2; exit 1; }
    done
    if [ -f "$src/gor-selftest.sh" ]; then
        if [ ! -f "$project_root/gor-selftest.sh" ] || ! cmp -s "$src/gor-selftest.sh" "$project_root/gor-selftest.sh"; then
            cp -p "$src/gor-selftest.sh" "$project_root/gor-selftest.sh.tmp" && mv "$project_root/gor-selftest.sh.tmp" "$project_root/gor-selftest.sh" || { echo "      install: copy failed for gor-selftest.sh" >&2; exit 1; }
        fi
    fi
    # Only explicit, hash-checked logger consolidation removals, already backed
    # up in changes.txt as deleted. No arbitrary absent-overlay file is removed.
    for rel in ${it_deleted[@]+"${it_deleted[@]}"}; do
        if ! rm -f "$project_root/$rel"; then
            echo "diag consolidation: retirement failed; restoring both originals" >&2
            local restore_rel restore_failed=false
            for restore_rel in ${it_deleted[@]+"${it_deleted[@]}"}; do
                cp -p "$rb_dir/$restore_rel" "$project_root/$restore_rel" || restore_failed=true
            done
            if [ "$restore_failed" = false ]; then
                # Avoid duplicate enums after restoring old files. Preserve the
                # newly installed replacement in this run's backup, never delete it.
                mv "$project_root/Sources/gor/Diag.swift" "$rb_dir/Diag.swift.failed-install" || {
                    echo "diag consolidation: replacement could not be parked; build refused" >&2; exit 1;
                }
            else
                echo "diag consolidation: rollback incomplete; backup=$rb_dir; build refused" >&2
            fi
            exit 1
        fi
    done
}

