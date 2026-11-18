# W-gdb-199h-wrr3-03 - Installed BuildID read (r3: rollback context + candidate identity)
state: OPEN / unclaimed
lab: shared stock (1nstinct + in2tinct; earliest claim wins, one holder)

arch-199h WR (r3, pinned to native50 35f553acd). BuildID reads <bundle>/Contents/Resources/build-id.txt; AppDelegate prints one bounded line per launch (excerpts below). r3 adds the actual rollback caller/build-script context lane c asked for: build.sh gor_update_restore_current_swap and the relaunch build-id logging (excerpts below). Scope: current-candidate BuildID comparison with a typed mismatch result, rollback caller wired to it, launch logging of the outcome. The authoritative expected candidate identity comes from the delivery receipt/baseline, never a guess.

Required acceptance: Linux tests: parser edge cases + candidate comparison outcomes; patch wires the rollback caller and launch line against the excerpted build.sh context.

Outcomes: a production change with executed semantic tests, or 'verified-not-needed with evidence' where this packet says so. The executed starter proof is a clean source-only materialization of exact pinned excerpts, not a full Swift package build. Full excerpts below are read-only input until this packet is claimed. Earliest claim wins across both labs; 2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs, or the evidence document. Preserve all existing supported behavior. Native compile queues after Linux verification (through the D1 route); native/UI/runtime NOT_RUN unless actually executed. No licensed bytes, no credentials.

```packet-json
{
 "packet_id": "W-gdb-199h-wrr3-03",
 "lab": "shared",
 "writer": "1nstinct or in2tinct (earliest claim wins)",
 "code_owner": "Claiming lab owns only the listed production files for this packet; integrator owns host wiring and move composition",
 "product_repo": "goreda/instinct",
 "product_sha": "35f553acd14333437db53253023c01137a9e843f",
 "touched_files": [
  {
   "path": "archive/gor/Sources/gor/GorCore/BuildID.swift",
   "excerpt_block": "buildid_full (lines 1-76)"
  },
  {
   "path": "archive/gor/Sources/gor/AppDelegate.swift",
   "excerpt_block": "buildid_full (lines 1-76)"
  },
  {
   "path": "archive/gor/build.sh",
   "excerpt_block": "buildid_full (lines 1-76)"
  }
 ],
 "interface": {
  "signatures": "BuildID reads <bundle>/Contents/Resources/build-id.txt; AppDelegate prints one bounded line per launch (excerpts below). r3 adds the actual rollback caller/build-script context lane c asked for: build",
  "types": "Existing declarations in exact pinned excerpts below; retain public APIs",
  "ownership_lifetime": "One writer per listed source file; 2h lease expires without holder commit; no gor U2/S2 host edits beyond the listed files",
  "caller": "Linux tests: parser edge cases + candidate comparison outcomes; patch wires the rollback caller and launch line against the excerpted build.sh context.",
  "callee": "archive/gor/Sources/gor/GorCore/BuildID.swift"
 },
 "scope": "product",
 "test": {
  "command": "python3 archive/gor/Tests/Architecture/199h-d5r3/W-gdb-199h-wrr3-03.py",
  "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires: Linux tests: parser edge cases + candidate comparison outcomes; patch wires the rollback caller and launch line against the excerpted build.sh context.",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "lane/lab-<claiming-lab>-W-gdb-199h-wrr3-03",
  "paths": [
   "archive/gor/Sources/gor/GorCore/BuildID.swift",
   "archive/gor/Sources/gor/AppDelegate.swift",
   "archive/gor/build.sh",
   "archive/gor/Tests/Architecture/199h-d5r3/W-gdb-199h-wrr3-03.py"
  ],
  "return_form": "patch"
 },
 "run_proof": {
  "version": 1,
  "product_repo": "goreda/instinct",
  "product_sha": "35f553acd14333437db53253023c01137a9e843f",
  "command": "python3 archive/gor/Tests/Architecture/199h-d5r3/W-gdb-199h-wrr3-03.py",
  "system": "Linux",
  "clean_checkout": true,
  "ran_at": "2026-11-18T10:48:08.763719+00:00",
  "kind": "module",
  "expected_exit": 0,
  "exit_code": 0,
  "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
  "inline_files": [
   {
    "path": "archive/gor/Sources/gor/GorCore/BuildID.swift",
    "lines": "1-76",
    "block": "Sources/gor/GorCore/BuildID.swift:1-76",
    "sha256": "544881ae92b8f6b4235ed47b70c14f4997ee10a05faa06d877d5bf8f3df80365"
   },
   {
    "path": "archive/gor/Sources/gor/AppDelegate.swift",
    "lines": "480-486",
    "block": "Sources/gor/AppDelegate.swift:480-486",
    "sha256": "0e4be0eca3c4f60035475fa5829ffafa6ddc1355ba34ab8e4d6bac49d83a84aa"
   },
   {
    "path": "archive/gor/build.sh",
    "lines": "1169-1200",
    "block": "build.sh:1169-1200",
    "sha256": "b240889f54c84b3262d8e5e1f9bcd234987489d512c7b141085121bd4787ab4e"
   },
   {
    "path": "archive/gor/build.sh",
    "lines": "980-990",
    "block": "build.sh:980-990",
    "sha256": "ced6a8c8dc0a504faf9ea5c0acda0e5f624035031a73765d2bdd40ce3c62b010"
   },
   {
    "path": "archive/gor/Tests/Architecture/199h-d5r3/W-gdb-199h-wrr3-03.py",
    "block": "fixtures1",
    "sha256": "769f1a80097220eb377b86fc601aa1249520654ad2c912ae7bb575572ea295fc"
   }
  ],
  "log_block": "actual_run_log",
  "log_sha256": "1629817bc698777a13f5a033dae6e5d21e01ea847a372f182c6299060553ca3f",
  "last_5_lines": [
   "BASELINE_SOURCE_PIN_PASS W-gdb-199h-wrr3-03; baseline only, product change and semantic test still required"
  ],
  "receipt_sha256": "701bf635badf89b20af4903efa6753844e10a7c4ca5b98a32c3ccec3ee9fd080"
 }
}
```

```swift id=Sources/gor/GorCore/BuildID.swift:1-76
import Foundation

/// K8(b): build identity shown in About and written to the synced log at launch.
/// Source: <bundle>/Contents/Resources/build-id.txt, written by build.sh.
/// The legacy key is commit=, but its value is the SHA256 of the compiled
/// source manifest, not a Git commit. Keep the format backward compatible.
/// A missing, unreadable or malformed file never crashes the app: the value is
/// "unknown" and the log line is still written on every launch (no skipping).
enum BuildID {
    static let resourceName = "build-id"
    static let resourceExtension = "txt"
    static let unknown = "unknown"

    /// Pure parser (no I/O). Returns the source identity value, or nil when the text has
    /// no usable `commit=` line (empty value or value containing whitespace).
    static func parseCommit(_ text: String) -> String? {
        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("commit=") else { continue }
            let value = String(line.dropFirst("commit=".count)).trimmingCharacters(in: .whitespaces)
            if value.isEmpty || value.contains(where: { $0.isWhitespace }) { return nil }
            return value
        }
        return nil
    }

    /// Value for display and log: the source identity, or "unknown".
    static func value(bundle: Bundle = .main) -> String {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let commit = parseCommit(text) else { return unknown }
        return commit
    }

    /// Pure parser (no I/O). Returns the delivered archive/gor tree sha, or nil when the
    /// text has no usable `tree=` line (must be exactly 40 lowercase hex chars).
    static func parseTree(_ text: String) -> String? {
        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("tree=") else { continue }
            let value = String(line.dropFirst("tree=".count)).trimmingCharacters(in: .whitespaces)
            guard value.count == 40, value.allSatisfy({ $0.isASCII && ($0.isNumber || ("a"..."f").contains($0)) }) else { return nil }
            return value
        }
        return nil
    }

    /// Delivered archive/gor tree sha, or "unknown". Same never-crash contract as value().
    static func tree(bundle: Bundle = .main) -> String {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let tree = parseTree(text) else { return unknown }
        return tree
    }

    /// UTC launch timestamp for the launch line (ISO 8601, seconds precision).
    static func launchTimestamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    /// Exact launch log line: installed BuildID sha, archive/gor tree sha, launch time.
    /// One bounded ASCII line per launch; gor-periodic-capture carries it to the repo.
    static func launchLine(value: String, tree: String, at: Date = Date()) -> String {
        let safeValue = (value.isEmpty || value.contains(where: { $0.isWhitespace })) ? unknown : value
        let safeTree = (tree.isEmpty || tree.contains(where: { $0.isWhitespace })) ? unknown : tree
        return "[GOR] build-id \(safeValue) tree=\(safeTree) launch=\(launchTimestamp(at))"
    }

    /// Short form for the About label (7 chars of the source identity, else as-is).
    static func shortValue(_ value: String) -> String {
        value == unknown ? unknown : String(value.prefix(7))
    }
}
```

```swift id=Sources/gor/AppDelegate.swift:480-486
        print("[GOR] bundleID: \(Bundle.main.bundleIdentifier ?? "nil"), path: \(Bundle.main.bundlePath), executable: \(CommandLine.arguments[0])")
        // K8(b): build identity line, written on every launch (including "unknown").
        // arch-199b: one bounded line per launch - installed BuildID sha, delivered
        // archive/gor tree sha, launch time. Nothing on screen; rides the capture route.
        print(BuildID.launchLine(value: BuildID.value(), tree: BuildID.tree()))
        
        NSApp.setActivationPolicy(StagedRunPaths.active ? .prohibited : .regular)
```

```bash id=build.sh:1169-1200
gor_update_restore_current_swap() {
    update_restore_detail="update red at $update_stage: no completed own-run swap; installed app unchanged"
    [ "${update_swap_completed:-false}" = true ] || return 0
    local marker="$stage_dir/.swap-done" backup="$stage_dir/gor.app.last"
    local failed="$stage_dir/gor.app.failed-update-$update_swap_token" actual
    # Selftest releases the build lock. Reacquire it before checking or moving
    # anything; another build may have replaced either app while tests ran.
    if [ "$(cat "$build_lock/pid" 2>/dev/null)" != "$$" ]; then
        if ! mkdir "$build_lock" 2>/dev/null; then
            update_restore_detail="update red: restore refused; another build owns the lock; apps preserved"
            return 1
        fi
        printf '%s\n' "$$" > "$build_lock/pid" || return 1
    fi
    if [ -L "$marker" ] || [ ! -f "$marker" ] ||
       [ "$(cat "$marker")" != "$update_swap_token" ] ||
       [ -z "${update_backup_identity:-}" ] ||
       [ -z "${update_candidate_identity:-}" ] ||
       [ "$(gor_app_identity "$backup" 2>/dev/null)" != "$update_backup_identity" ] ||
       [ "$(gor_app_identity "$installed_app" 2>/dev/null)" != "$update_candidate_identity" ] ||
       [ -e "$failed" ] || [ -L "$failed" ]; then
        update_restore_detail="update red: restore refused; own-run app/backup/marker changed or park path occupied; apps preserved"
        return 1
    fi
    if ! stop_running_gor; then
        update_restore_detail="update red: restore refused; current app did not stop; apps preserved"
        return 1
    fi
    # Recheck after waiting for the process to stop, before the first rename.
    [ "$(cat "$marker")" = "$update_swap_token" ] &&
    [ "$(gor_app_identity "$backup" 2>/dev/null)" = "$update_backup_identity" ] &&
    [ "$(gor_app_identity "$installed_app" 2>/dev/null)" = "$update_candidate_identity" ] || return 1
```

```bash id=build.sh:980-990

    if [ "$selftest_mode" = full ] && [ -f "$project_root/tools/owner_action_acceptance.py" ]; then
        st_note "KNOWN-RESIDUAL base02004a518: cinema_pose ShiftR pin; preview_pack two text pins; row_wiring ShiftD pin; old onBack2D test API; gpu_pose D3_TITLE_tex; surface_anchor old output pin; axes_gpu killed on base and candidate, incomplete"; st_quit || true; if st_wait_gone 30; then for owner_kind in ordinary native; do owner_rc=0; owner_arg=""; [ "$owner_kind" != native ] || owner_arg="--native"; owner_out=$(GOR_STEP_LIMIT=90 /usr/bin/python3 "$project_root/tools/gor_step.py" "owner action $owner_kind" /usr/bin/python3 "$project_root/tools/owner_action_acceptance.py" "$project_root" $owner_arg 2>&1) || owner_rc=$?; printf '%s\n' "$owner_out" | while IFS= read -r line; do st_note "$line"; done; st_note "3D-OWNER-ACTION leg=$owner_kind rc=$owner_rc"; if [ "$owner_rc" = 2 ]; then store_not_run=true; elif [ "$owner_rc" != 0 ]; then st_fail "owner-action-$owner_kind" "applied-state acceptance failed; see receipts"; fi; done; else st_note "NOT_RUN owner-actions prior interactive process still running"; store_not_run=true; fi
    fi
    if [ "$selftest_mode" != full ]; then st_note "3D kabul: calistirilmadi"; fi
    st_quit || true; if st_wait_gone 30; then st_note "RELAUNCH prior_exact_path_processes=gone requested_epoch=$(date +%s)"; open -g -n "$app" --args --gor-background-start 2>/dev/null || st_fail t1-relaunch-open "explicit app launch failed"; else st_fail t1-relaunch-fresh "prior exact-path process did not quit"; fi
    if st_wait_running 60; then for fresh_pid in $(/usr/bin/python3 "$project_root/tools/axes_acceptance.py" --list-interactive "$bin"); do st_note "RELAUNCH pid=$fresh_pid started=$(ps -p "$fresh_pid" -o lstart=) $(tr '\n' ' ' < "$app/Contents/Resources/build-id.txt")"; done; echo "gor left running."; else st_fail t1-relaunch-stay "app not running after final relaunch"; fi
    if [ "$fail" -eq 0 ] && [ "$store_not_run" = true ]; then st_note "SELFTEST PARTIAL $pass passed; store-acceptance NOT_RUN"; elif [ "$fail" -eq 0 ]; then
        st_note "SELFTEST PASS $pass/$((pass+fail)) $(( $(date +%s) - t0 ))s"
    else
        st_note "SELFTEST FAIL $pass/$((pass+fail)) $(( $(date +%s) - t0 ))s"
```

```python id=fixtures1
from pathlib import Path
import hashlib, os, sys
sys.dont_write_bytecode = True
ROOT = Path(os.environ.get("PRODUCT_ROOT", Path(__file__).resolve().parents[3]))
CHECKS = [["Sources/gor/GorCore/BuildID.swift", 1, 76, "544881ae92b8f6b4235ed47b70c14f4997ee10a05faa06d877d5bf8f3df80365"], ["Sources/gor/AppDelegate.swift", 480, 486, "0e4be0eca3c4f60035475fa5829ffafa6ddc1355ba34ab8e4d6bac49d83a84aa"], ["build.sh", 1169, 1200, "b240889f54c84b3262d8e5e1f9bcd234987489d512c7b141085121bd4787ab4e"], ["build.sh", 980, 990, "ced6a8c8dc0a504faf9ea5c0acda0e5f624035031a73765d2bdd40ce3c62b010"]]
bad = []
for rel, a, b, want in CHECKS:
    lines = (ROOT / rel).read_text().splitlines(keepends=True)
    data = "".join(lines[a-1:b]).encode()
    got = hashlib.sha256(data).hexdigest()
    if got != want:
        bad.append((rel, a, b, got))
if bad:
    for rel, a, b, got in bad:
        print("PIN_MISMATCH " + rel + ":" + str(a) + "-" + str(b) + " got=" + got)
    sys.exit(1)
print("BASELINE_SOURCE_PIN_PASS W-gdb-199h-wrr3-03; baseline only, product change and semantic test still required")
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-199h-wrr3-03; baseline only, product change and semantic test still required
```
