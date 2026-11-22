#!/usr/bin/env python3
"""191l no-auto-restore pins (owner order 01:25: only he rolls back).

--update NEVER reverts: no automatic restore/revert remains at any stage. A red compile,
launch, or selftest leaves the installed gor.app as-is, keeps the previous app intact at
.gor-stage/gor.app.last (when the run swapped), reports the stage + the one manual restore
command, and stops. The old build returns only via his explicit
`bash build.sh --no-build --rollback`.
Guarantees pinned here:
  * gor_update_red_restore is GONE - no caller, no definition
  * the trap's red branch (any stage before result) only reports; the detail reaches the
    capture detail block and the owner's terminal, and names the manual rollback command
  * the swap marker stays run-scoped, so a compile failure (before any swap) never touches
    the installed app by construction
  * the swap-install failure hygiene stays: a failed install mv moves the previous app back
    (that is "failure leaves the previous app intact", not a revert of a good install)
  * relaunch identity: success registers ONLY the canonical bundle and unregisters
    same-bundle-id asides (gor.app.last, gor.app.instinct-*, parked gor-bbu copies)
  * build.sh stays at or under the 2773-line ceiling and bash -n clean
  * pin3: a red swift build with zero extracted diagnostics posts a bounded scrubbed tail
The functional legs run on Linux: the trap's red branch is extracted from build.sh and
exercised in bash against a scratch project tree; the full-Mac proof stays the update capture."""
import re, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BS = ROOT / "build.sh"
TEXT = BS.read_text()

fails = 0
def check(name, ok, extra=""):
    global fails
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else "\n" + str(extra)))
    fails += 0 if ok else 1

# ---- static pins -------------------------------------------------------------
check("build.sh at or under the 2773-line ceiling", TEXT.count("\n") <= 2773, TEXT.count("\n"))
syntax = subprocess.run(["bash", "-n", str(BS)], capture_output=True, text=True)
check("build.sh is valid bash", syntax.returncode == 0, syntax.stderr)

check("gor_update_red_restore has no definition and no caller (191l)",
      "gor_update_red_restore" not in TEXT)
check("no gor-bbu auto-park of a failed build remains",
      "update-red-restore" not in TEXT)

trap = TEXT.split("gor_update_exit_trap() {", 1)[1].split("\n}", 1)[0]
check("trap red branch reports instead of restoring, before the result commit",
      "NO auto-restore (191l" in trap and
      trap.find("NO auto-restore") < trap.find('gor_update_result_commit "$rc"'), trap)
check("trap names the stage, the intact previous app, and the manual rollback command",
      "$update_stage" in trap and "$stage_dir/gor.app.last" in trap and
      "bash build.sh --no-build --rollback" in trap, trap)
check("red detail reaches the capture detail block",
      '"${update_restore_detail:-}"' in TEXT and 'for ud in "${update_compile_detail:-}" "${update_restore_detail:-}"' in TEXT)
check("red detail also reaches the owner's terminal", 'echo "$update_restore_detail"' in trap)
check("result commit still gated to exactly one attempt", '"$update_result_attempted" != true' in trap)
check("swap marker is run-scoped at update start (compile-fail leg never touches the installed app)",
      '"${update_mode:-false}" = true ] && rm -f "$stage_dir/.swap-done"' in TEXT)

rollback = TEXT.split("gor_rollback() {", 1)
check("manual --rollback path still exists", len(rollback) == 2)
check("rollback is reached only from argument parsing, never from the trap or the swap",
      "gor_rollback" not in trap and "gor_rollback" not in TEXT.split("gor_swap_install() {", 1)[1].split("\n}", 1)[0])

swap = TEXT.split("gor_swap_install() {", 1)[1]
check("swap failure hygiene retained: failed install mv moves the previous app back",
      "swap: install failed; moving the previous app back" in swap)
check("swap failure with no previous app says so plainly",
      "swap: install failed; no previous app exists - nothing to restore" in swap)

check("success registers the canonical bundle and unregisters same-bundle-id asides (relaunch identity)",
      'lsregister -f "$app_bundle"' in TEXT and
      'lsregister -u "$_dup"' in TEXT and
      '"$stage_dir/gor.app.last" "$project_root"/gor.app.instinct-* "$HOME/Downloads/gor-bbu"/*/gor.app' in TEXT)
check("aside unregister failure can never abort the update: lsregister -u guarded inside the and-list body",
      'lsregister -u "$_dup" 2>/dev/null || true; }' in TEXT)

check("launch asks LaunchServices for the exact installed bundle, never a name lookup",
      'open -n "$app_bundle"' in TEXT and
      not any(l.strip().startswith('open -a') for l in TEXT.splitlines() if not l.strip().startswith('#')))

# ---- functional legs (Linux, bash): the trap's red branch moves nothing ------
RED = next(l for l in TEXT.splitlines() if "NO auto-restore (191l" in l)
RED = RED.split("; fi;", 1)[0] + "; fi"   # only the red-report branch; the result-commit branch follows on the same line
def run_case(name, stage, make_swap_done, make_last):
    with tempfile.TemporaryDirectory() as td:
        base = Path(td); staged = base / ".gor-stage"; home = base / "home"
        staged.mkdir(parents=True); home.mkdir()
        if make_last:
            (staged / "gor.app.last" / "Contents").mkdir(parents=True)
            (staged / "gor.app.last" / "Contents" / "marker").write_text("LAST")
        if make_swap_done:
            (staged / ".swap-done").write_text("")
        (base / "gor.app" / "Contents").mkdir(parents=True)
        (base / "gor.app" / "Contents" / "marker").write_text("NEW")
        script = (f'rec() {{ :; }}\nrc=1; update_stage="{stage}"; update_result_attempted=true; '
                  f'stage_dir="{staged}"; installed_app="{base}/gor.app"; project_root="{base}"; HOME="{home}"; '
                  f'update_restore_detail=""\n{RED}\nprintf "DETAIL:%s\\n" "$update_restore_detail"')
        r = subprocess.run(["bash", "-c", script], capture_output=True, text=True)
        def read(p):
            return p.read_text() if p.exists() else None
        return {
            "rc": r.returncode, "err": r.stderr,
            "installed": read(base / "gor.app" / "Contents" / "marker"),
            "last": read(staged / "gor.app.last" / "Contents" / "marker"),
            "swap_done": (staged / ".swap-done").exists(),
            "parked": list(home.glob("Downloads/gor-bbu/**")),
            "detail": next((l for l in r.stdout.splitlines() if l.startswith("DETAIL:")), ""),
        }

s = run_case("selftest-red-with-swap", "selftest", True, True)
check("selftest red: installed app left as-is, previous app intact, nothing parked",
      s["rc"] == 0 and s["installed"] == "NEW" and s["last"] == "LAST" and not s["parked"], s["err"] + s["detail"])
check("selftest red: report names the stage and the manual rollback command",
      "update red at selftest" in s["detail"] and "bash build.sh --no-build --rollback" in s["detail"], s["detail"])

s = run_case("launch-fail-with-swap", "build", True, True)
check("launch fail (build stage): installed app left as-is, previous app intact, nothing parked",
      s["rc"] == 0 and s["installed"] == "NEW" and s["last"] == "LAST" and not s["parked"], s["err"] + s["detail"])
check("launch fail: report names the stage and the manual rollback command",
      "update red at build" in s["detail"] and "bash build.sh --no-build --rollback" in s["detail"], s["detail"])

s = run_case("compile-fail-no-swap", "build", False, False)
check("compile fail: no swap, installed app untouched, nothing parked",
      s["rc"] == 0 and s["installed"] == "NEW" and s["last"] is None and not s["parked"], s["err"] + s["detail"])
check("compile fail: report still names the manual rollback command",
      "bash build.sh --no-build --rollback" in s["detail"], s["detail"])

# ---- stale-axes retirement (191b): the overlay install never deletes, so the kit retires it ----
axes = TEXT.split('if [ -f "$project_root/Sources/gor/ThreeDAxesAcceptance.swift" ]; then axes_rb=', 1)
check("axes retirement block present", len(axes) == 2)
if len(axes) == 2:
    block = axes[1].split('backup=$axes_rb"; fi', 1)[0]
    check("retirement backs up before removing (cp && changes.txt && rm order)",
          block.find("cp -p") != -1 and block.find("cp -p") < block.find("changes.txt") < block.find("rm -f"), block[:200])
    check("retirement records a rollback-compatible deleted row",
          "printf 'deleted\\tSources/gor/ThreeDAxesAcceptance.swift\\n' > \"$axes_rb/changes.txt\"" in block)
    check("retirement failure refuses the build loudly", 'build refused' in block and 'exit 1' in block)
    check("retirement parks under the standard backups dir with a timecode-operation name",
          '"$backups_dir/$(date +%y%m%d-%H%M%S)-axes-retire"' in block)
    check("retirement runs after the domain consolidation, before the build",
          TEXT.find('Tests/Structure/migrate.py') < TEXT.find('ThreeDAxesAcceptance.swift" ]; then axes_rb=') < TEXT.find('[ "$skip_build" = true ]'))

with tempfile.TemporaryDirectory() as td:
    base = Path(td); proj = base / "proj"; bdir = base / "backups"
    (proj / "Sources/gor").mkdir(parents=True); bdir.mkdir()
    stale = proj / "Sources/gor/ThreeDAxesAcceptance.swift"; stale.write_text("// stale axes runner\n")
    lines = TEXT.splitlines()
    start = next(i for i, l in enumerate(lines) if 'axes_rb=' in l and 'ThreeDAxesAcceptance.swift' in l)
    block_sh = "\n".join(lines[start:start + 3])
    script = f'set -e; project_root="{proj}"; backups_dir="{bdir}"' + chr(10) + block_sh
    r = subprocess.run(["bash", "-c", script], capture_output=True, text=True)
    parked = list(bdir.glob("*-axes-retire/Sources/gor/ThreeDAxesAcceptance.swift"))
    changes = list(bdir.glob("*-axes-retire/changes.txt"))
    check("functional: stale axes file retired from the project tree", r.returncode == 0 and not stale.exists(), r.stderr)
    check("functional: bytes preserved in the backup with a deleted row",
          len(parked) == 1 and parked[0].read_text() == "// stale axes runner\n" and
          len(changes) == 1 and changes[0].read_text() == "deleted\tSources/gor/ThreeDAxesAcceptance.swift\n", r.stderr)
    r2 = subprocess.run(["bash", "-c", script], capture_output=True, text=True)
    check("functional: no stale file means no-op", r2.returncode == 0, r2.stderr)

# ---- pin3: a red swift build posts a bounded scrubbed tail when no diagnostics match ----
check("bounded scrubbed tail pinned in build.sh (pin3)",
      "current-update-build-tail (stage=swift build, no diagnostics matched; last 200 lines scrubbed):" in TEXT)

print("update_red_restore_test: " + ("PASS" if fails == 0 else f"FAIL ({fails})"))
sys.exit(0 if fails == 0 else 1)
