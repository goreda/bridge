#!/bin/bash
set -e
if [ -t 1 ]; then clear && printf '\033[3J'; fi

# GOR_BUILD_SCOPE_BEGIN
# Lock the physical project before touching shared logs, staging or processes.
project_root="$(cd "$(dirname "$0")" && pwd -P)"
build_lock="$project_root/.gor-build.lock"
if ! mkdir "$build_lock" 2>/dev/null; then
    echo "Another build or an interrupted-build lock exists: $build_lock" >&2
    echo 'Nothing changed. Do not remove a lock while its build is running.' >&2
    exit 1
fi
printf '%s\n' "$$" > "$build_lock/pid"
gor_release_build_lock() {
    # Remove only the lock acquired by this invocation, not another build's.
    if [ "$(cat "$build_lock/pid" 2>/dev/null)" = "$$" ]; then
        rm -f "$build_lock/pid"
        rmdir "$build_lock" 2>/dev/null || true
    fi
}
trap gor_release_build_lock EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cd "$project_root"
# GOR_BUILD_SCOPE_END
start_time=$(date +%s)
# A previous aborted launch must not be mistaken for this build.
playback_marker="/tmp/gor-build-playback-start.marker"
rm -f "$playback_marker"

# ── config ────────────────────────────────────────────────────────────────────
open_app=true          # launch after build
exit_log_zip=true      # install post-exit log watcher and next-launch recovery
log_timestamp=true     # true/false: timestamp on every captured log line
log_cpu_info=true      # true/false: cached system CPU percent and CPU sensor temperature
log_mode="direct"      # log mode after launch (see LOG MODES below)
show_warnings=false    # show swift compiler warnings (can be noisy)
separate_build_log=false # true: retain all printed build/sign/install output plus unfiltered Swift in /tmp/gor_build.log
create_dmg=false       # package as .dmg
clean_build=false      # delete .build/ before compiling
signing_enabled=true   # stable MacDev identity preferred for local TCC grants
signing_mode="dev"    # dev: stable MacDev identity; distribution: full deep verify
vendor_layout="sealed" # sealed (safe default) or linked-dev (local iteration only)
# WHY: sealing hundreds of MB of vendor resources costs ~27s every build.
# linked-dev seals a symlink to a versioned, separately signed vendor snapshot.
build_whisper=false    # also build whisper-live before the swift build (see WHISPER-LIVE below)

# ── whisper-live ──────────────────────────────────────────────────────────────
# whisper_src_dir points at the whisper.cpp checkout that contains
# examples/whisper-live/main.cpp (defined below, right after project_root —
# it depends on project_root, so it can't be set up here in the config
# block). `cmake --build` is incremental on its own (it no-ops in ~1s when
# nothing under whisper.cpp or main.cpp changed), so build_whisper=true is
# safe to leave on by default once you're iterating on whisper-live itself
# — it won't meaningfully slow down a run where nothing there changed.

# ── LOG MODES ─────────────────────────────────────────────────────────────────
#   off      — no log output. fast iteration when everything works.
#   direct   — exec binary directly in terminal. raw stdout+stderr, mpv output
#              included. cleanest signal for AI-paste debugging sessions.
#              WARNING: may hit TCC -3801 if screen-recording not pre-granted.
#              if it fails, falls back to filter mode automatically.
#   filter   — log stream filtered to [GOR] prefix only. zero noise.
#              use this for targeted feature testing: add NSLog(@"[GOR] ...")
#              to the code path under test, paste output directly to AI.
#              token-efficient: only your signal, nothing else.
#   stream   — log stream scoped to gor process. standard NSLog output.
#              useful for general session debug without code changes.
#   broad    — log stream: gor + mpv + Python (mus2.py). catches os_log from
#              subprocesses. use when tracing cross-process behavior.
#              note: raw print() and mpv stderr not capturable via open -a.
#   full     — log stream with no predicate filter. entire system output.
#              last resort only — when you don't know which subsystem is firing.

# Exactly one writer owns gor_build.log. Both printed output and unfiltered
# compiler records enter its FIFO; nobody else opens the destination file.
separate_log_dir=""
separate_log_pid=""
exec 4>&1
if [ "$separate_build_log" = true ]; then
    separate_log_dir=$(mktemp -d /tmp/gor-build-capture.XXXXXX)
    mkfifo "$separate_log_dir/input"
    tee /tmp/gor_build.log < "$separate_log_dir/input" >/dev/null &
    separate_log_pid=$!
    exec 5>"$separate_log_dir/input"
    exec > >(tee /dev/fd/5 >&4) 2>&1
else
    rm -f /tmp/gor_build.log
fi

# ── args — override config flags without editing the file ─────────────────────
# usage: ./build.sh [--no-launch] [--clean] [--dmg] [--no-sign] [--distribution] [--fast-dev] [--warnings]
#                   [--whisper] [--log off|direct|filter|stream|broad|full]
while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-log-timestamp) log_timestamp=false ;;
        --no-log-cpu-info) log_cpu_info=false ;;
        --log-timestamp) log_timestamp=true ;;
        --log-cpu-info) log_cpu_info=true ;;
        --no-launch) open_app=false ;;
        --clean)     clean_build=true ;;
        --dmg)       create_dmg=true ;;
        --no-sign)   signing_enabled=false ;;
        --distribution) signing_mode="distribution" ;;
        --fast-dev) vendor_layout="linked-dev" ;;
        --warnings)  show_warnings=true ;;
        --whisper)   build_whisper=true ;;
        --log)
            shift
            if [ "$#" -eq 0 ]; then echo "--log needs a mode" >&2; exit 2; fi
            log_mode="$1" ;;
        *) echo "unknown build option: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$log_mode" in
    off|direct|filter|stream|broad|full) ;;
    *) echo "unknown log mode: $log_mode" >&2; exit 2 ;;
esac

case "$vendor_layout" in
    sealed|linked-dev) ;;
    *) echo "unknown vendor layout: $vendor_layout" >&2; exit 2 ;;
esac
if [ "$vendor_layout" = linked-dev ]; then
    if [ "$signing_mode" = distribution ] || [ "$create_dmg" = true ]; then
        echo "linked-dev vendor cannot be distributed or packaged; use sealed layout" >&2
        exit 2
    fi
    if [ "$signing_enabled" != true ]; then
        echo "linked-dev requires signed vendor binaries; omit --no-sign" >&2
        exit 2
    fi
fi

case "$log_timestamp:$log_cpu_info" in
    true:true|true:false|false:true|false:false) ;;
    *) echo "log_timestamp/log_cpu_info must be true or false" >&2; exit 2 ;;
esac
# Compile before installing capture; failure is explicit, never silently raw.
log_writer_dir=$(mktemp -d /tmp/gor-log-writer.XXXXXX)
log_writer="$log_writer_dir/gor-log-writer"
log_writer_enabled=false
# Writer source is embedded here on purpose: it has top-level code, so it must
# never sit as a .swift file inside Sources/gor (SwiftPM would reject it).
cat > "$log_writer_dir/main.swift" <<'GOR_LOG_WRITER_EOF'
// Standalone line writer shared by build.sh and the app. No privileged tools.
import Foundation
import Darwin
import IOKit

private let args = CommandLine.arguments
private func value(_ key: String, _ fallback: String) -> String {
    guard let i = args.firstIndex(of: key), i + 1 < args.count else { return fallback }
    return args[i + 1]
}
private let timestampEnabled = value("--timestamp", "true") == "true"
private let cpuEnabled = value("--cpu-info", "true") == "true"
private let echoEnabled = !args.contains("--quiet")
private let destination = value("--output", "/tmp/gor_direct.log")
private let output = open(destination, O_WRONLY | O_CREAT | O_APPEND, 0o600)
guard output >= 0 else { exit(1) }
private let sampleLock = NSLock()
private var sampledAt: UInt64 = 0
private var cpuPercent: Double?
private var cpuTemperature: Double?
private var previousTicks: [UInt32]?
private let hostPort = mach_host_self()
private let clock = ISO8601DateFormatter()
clock.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

// Private HID API is optional. Missing symbols/sensors never become zero C.
private final class CPUThermometer {
    typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    typealias Match = @convention(c) (CFTypeRef, CFDictionary) -> Int32
    typealias Services = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    typealias Property = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    typealias Event = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    typealias FloatValue = @convention(c) (CFTypeRef, Int32) -> Double
    private let library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
    private func symbol<T>(_ name: String, _ type: T.Type) -> T? {
        guard let library, let address = dlsym(library, name) else { return nil }
        return unsafeBitCast(address, to: type)
    }
    func read() -> Double? {
        guard let create = symbol("IOHIDEventSystemClientCreate", Create.self),
              let match = symbol("IOHIDEventSystemClientSetMatching", Match.self),
              let services = symbol("IOHIDEventSystemClientCopyServices", Services.self),
              let property = symbol("IOHIDServiceClientCopyProperty", Property.self),
              let event = symbol("IOHIDServiceClientCopyEvent", Event.self),
              let floatValue = symbol("IOHIDEventGetFloatValue", FloatValue.self),
              let client = create(nil)?.takeRetainedValue() else { return nil }
        _ = match(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        guard let list = services(client)?.takeRetainedValue() else { return nil }
        var temperatures = [Double]()
        for service in list as [AnyObject] {
            guard let product = property(service, "Product" as CFString)?.takeRetainedValue() as? String,
                  product.hasPrefix("eACC MTR Temp Sensor") || product.hasPrefix("pACC MTR Temp Sensor"),
                  let reading = event(service, 15, 0, 0)?.takeRetainedValue() else { continue }
            let degrees = floatValue(reading, 15 << 16)
            if degrees.isFinite && degrees > 0 && degrees < 150 { temperatures.append(degrees) }
        }
        return temperatures.isEmpty ? nil : temperatures.reduce(0, +) / Double(temperatures.count)
    }
}
private let thermometer = CPUThermometer()
private let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "gor.log.sample", qos: .utility))
if cpuEnabled {
    timer.schedule(deadline: .now(), repeating: 1)
    timer.setEventHandler {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        var percent: Double?
        if status == KERN_SUCCESS {
            let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
            if let previous = previousTicks {
                let deltas = zip(ticks, previous).map { UInt64($0.0 &- $0.1) }
                let total = deltas.reduce(0, +)
                if total > 0 { percent = 100 * Double(total - deltas[Int(CPU_STATE_IDLE)]) / Double(total) }
            }
            previousTicks = ticks
        }
        let temperature = thermometer.read()
        sampleLock.lock()
        cpuPercent = percent
        cpuTemperature = temperature
        sampledAt = DispatchTime.now().uptimeNanoseconds
        sampleLock.unlock()
    }
    timer.resume()
}
private func number(_ value: Double?) -> String {
    value.map { String(format: "%.1f", $0) } ?? "unavailable"
}
private func writeAll(_ fd: Int32, _ bytes: Data) -> Bool {
    bytes.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { return true }
        var offset = 0
        while offset < bytes.count {
            let n = Darwin.write(fd, base.advanced(by: offset), bytes.count - offset)
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { return false }
            offset += n
        }
        return true
    }
}
private func emit(_ body: Data, partial: Bool = false) {
    var fields = [String]()
    if timestampEnabled { fields.append("ts=" + clock.string(from: Date())) }
    if cpuEnabled {
        sampleLock.lock()
        let age = sampledAt == 0 ? nil : Double(DispatchTime.now().uptimeNanoseconds - sampledAt) / 1e9
        let fresh = age.map { $0 <= 3 } ?? false
        let cpu = fresh ? cpuPercent : nil
        let temperature = fresh ? cpuTemperature : nil
        sampleLock.unlock()
        fields += ["cpu_system_pct=" + number(cpu), "cpu_temp_c=" + number(temperature),
                   "sample_age_s=" + number(age), "temp_source=hid_cpu_average"]
    }
    var row = Data((fields.isEmpty ? "" : "[" + fields.joined(separator: " ") + "] ").utf8)
    row.append(body)
    if !partial { row.append(10) }
    // Build compiler capture and runtime writers can append concurrently.
    // Serialize the complete record, including any short-write retries.
    guard flock(output, LOCK_EX) == 0 else { exit(1) }
    let written = writeAll(output, row)
    _ = flock(output, LOCK_UN)
    if !written { exit(1) }
    if echoEnabled { _ = writeAll(STDOUT_FILENO, row) }
}
var pending = Data()
var buffer = [UInt8](repeating: 0, count: 8192)
while true {
    let count = Darwin.read(STDIN_FILENO, &buffer, buffer.count)
    if count < 0 && errno == EINTR { continue }
    if count <= 0 { break }
    pending.append(contentsOf: buffer.prefix(count))
    while let newline = pending.firstIndex(of: 10) {
        emit(Data(pending[..<newline]))
        pending.removeSubrange(...newline)
    }
    // Bound unbroken binary/no-newline output, retaining bytes as partial fragments.
    if pending.count >= 1_048_576 { emit(pending, partial: true); pending.removeAll(keepingCapacity: true) }
}
if !pending.isEmpty { emit(pending, partial: true) }
mach_port_deallocate(mach_task_self_, hostPort)
close(output)
GOR_LOG_WRITER_EOF
if xcrun swiftc "$log_writer_dir/main.swift" -o "$log_writer"; then
    echo "[GOR] signing log writer"
    if codesign --force --sign - "$log_writer"; then
        echo "[GOR] log writer signature ready"
        log_writer_enabled=true
    else
        echo "[GOR] log writer signing failed: raw log, no timestamp/cpu"
    fi
else
    echo "[GOR] log writer compile failed: raw log, no timestamp/cpu"
fi
append_direct_log() {
    # Compiler output bypasses the normal stdout filter. Feed the same full
    # record to the sole separate-log writer, never a second file writer.
    if [ "$separate_build_log" = true ]; then cat "$1" >&5; fi
    if [ "$log_writer_enabled" = true ]; then
        "$log_writer" --quiet --timestamp "$log_timestamp" --cpu-info "$log_cpu_info" < "$1"
    else
        cat "$1" >> /tmp/gor_direct.log
    fi
}
# Capture all build output in the direct log regardless of launch/log mode.
# AppDelegate appends its runtime output to this same file after launch.
: > /tmp/gor_direct.log
exec 3>&1
if [ "$log_writer_enabled" = true ]; then
    exec > >("$log_writer" --timestamp "$log_timestamp" --cpu-info "$log_cpu_info" >&3) 2>&1
else
    exec > >(tee -a /tmp/gor_direct.log >&3) 2>&1
fi

# One EXIT cleanup owns scratch files and this build's log viewer.
# Dock launches write the same log, so never leave a tail attached to this tty.
whisper_build_log=""
temporary_build_log=""
source_snapshot=""
exclude_file=""
manifest_tmp=""
metadata_tmp=""
dev_vendor_snapshot=""
dev_vendor_committed=false
TAILPID=""
stop_log_viewer() {
    if [ -n "$TAILPID" ]; then
        kill "$TAILPID" 2>/dev/null || true
        # Viewer has no state to save. KILL also covers an exit-before-exec
        # race where its background shell has not reset inherited traps yet.
        kill -KILL "$TAILPID" 2>/dev/null || true
        wait "$TAILPID" 2>/dev/null || true
        TAILPID=""
    fi
}
cleanup_build_run() {
    stop_log_viewer
    if [ -n "$separate_log_dir" ]; then rm -rf "$separate_log_dir" || true; fi
    rm -rf "$log_writer_dir"
    local scratch
    for scratch in "$whisper_build_log" "$temporary_build_log" \
        "$exclude_file" "$manifest_tmp" "$metadata_tmp" "$source_snapshot"; do
        if [ -n "$scratch" ]; then rm -f "$scratch" || true; fi
    done
    if [ -n "$dev_vendor_snapshot" ] && [ "$dev_vendor_committed" != true ]; then
        rm -rf "$dev_vendor_snapshot" || true
    fi
    gor_release_build_lock
}
trap cleanup_build_run EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ── paths ─────────────────────────────────────────────────────────────────────
app_name="gor"
bundle_id="com.gokcebalkan.gor"
# project_root is already fixed and locked before any shared side effects.
icon_source="$project_root/Resources/icon/_icon.png"

build_dir="$project_root/.build"
debug_bin=""  # Resolved from SwiftPM after a successful product build.
app_bundle="$project_root/$app_name.app"
staged_bundle="$project_root/$app_name.app.new"
dest="$staged_bundle/Contents/MacOS"
res="$staged_bundle/Contents/Resources"
icon_cache="$build_dir/AppIcon.icns"
whisper_src_dir="$project_root/whisper-cpp-src"

total_steps=7
if [ "$build_whisper" = true ]; then
    total_steps=8
fi
step=0
step_name=""
step_started=$start_time
finish_step() {
    if [ -n "$step_name" ]; then
        now=$(date +%s)
        printf '      timing: %s %ss\n' "$step_name" "$((now - step_started))"
    fi
}
next_step() {
    finish_step
    step=$((step + 1))
    step_name=$1
    step_started=$(date +%s)
    printf '[%d/%d] ' "$step" "$total_steps"
}

# ── kill running instance ─────────────────────────────────────────────────────
next_step cleaning; echo "cleaning..."
# Stop this user's gor instances and verify exit before touching the bundle.
# A timed-out SIGTERM must not leave the old process alive through the swap.
build_uid=$(id -u)
gor_pids() {
    local status
    if pgrep -u "$build_uid" -x "$app_name"; then
        return 0
    else
        status=$?
        [ "$status" -eq 1 ] && return 0
        echo "      cannot check running gor processes (pgrep status $status)" >&2
        return "$status"
    fi
}
# Keep mpv identities before gor exits: PPID alone no longer works after reparenting.
# lstart + uid + executable narrows PID-reuse risk without killing unrelated mpv.
mpv_identity() {
    ps -p "$1" -o uid= -o lstart= -o comm= 2>/dev/null | awk '{$1=$1; print}'
}
remember_mpv_children() {
    local parent children child identity status index known
    for parent in $1; do
        if children=$(pgrep -u "$build_uid" -P "$parent" -x mpv); then
            :
        else
            status=$?
            if [ "$status" -ne 1 ]; then
                echo "      cannot check gor mpv children (pgrep status $status)" >&2
                return "$status"
            fi
            children=""
        fi
        for child in $children; do
            known=false
            for ((index = 0; index < ${#mpv_pids[@]}; index++)); do
                [ "${mpv_pids[$index]}" != "$child" ] || known=true
            done
            [ "$known" = false ] || continue
            identity=$(mpv_identity "$child")
            [ -n "$identity" ] || continue
            mpv_pids[${#mpv_pids[@]}]=$child
            mpv_identities[${#mpv_identities[@]}]=$identity
            echo "      tracking gor mpv child PID: $child"
        done
    done
}
tracked_mpv_alive() {
    local current
    current=$(mpv_identity "${mpv_pids[$1]}")
    [ -n "$current" ] && [ "$current" = "${mpv_identities[$1]}" ]
}
stop_tracked_mpv() {
    local index attempt alive
    for ((index = 0; index < ${#mpv_pids[@]}; index++)); do
        if tracked_mpv_alive "$index"; then
            echo "      stopping tracked gor mpv PID: ${mpv_pids[$index]}"
            kill -TERM "${mpv_pids[$index]}" 2>/dev/null || true
        fi
    done
    for ((attempt = 0; attempt < 10; attempt++)); do
        alive=false
        for ((index = 0; index < ${#mpv_pids[@]}; index++)); do
            if tracked_mpv_alive "$index"; then alive=true; fi
        done
        [ "$alive" = true ] || return 0
        sleep 0.2
    done
    for ((index = 0; index < ${#mpv_pids[@]}; index++)); do
        if tracked_mpv_alive "$index"; then
            echo "      mpv did not exit after SIGTERM; sending SIGKILL to: ${mpv_pids[$index]}"
            kill -KILL "${mpv_pids[$index]}" 2>/dev/null || true
        fi
    done
    for ((attempt = 0; attempt < 10; attempt++)); do
        alive=false
        for ((index = 0; index < ${#mpv_pids[@]}; index++)); do
            if tracked_mpv_alive "$index"; then alive=true; fi
        done
        [ "$alive" = true ] || return 0
        sleep 0.2
    done
    echo "      tracked gor mpv is still running; refusing bundle replacement/launch" >&2
    return 1
}
stop_running_gor() {
    local pids attempt
    local mpv_pids=() mpv_identities=()
    pids=$(gor_pids)
    [ -n "$pids" ] || return 0
    remember_mpv_children "$pids"
    echo "      stopping gor PID(s): $pids"
    kill -TERM $pids 2>/dev/null || true
    for ((attempt = 0; attempt < 50; attempt++)); do
        pids=$(gor_pids)
        [ -n "$pids" ] || break
        remember_mpv_children "$pids"
        sleep 0.2
    done
    pids=$(gor_pids)
    if [ -n "$pids" ]; then
        remember_mpv_children "$pids"
        echo "      gor did not exit after SIGTERM; sending SIGKILL to: $pids"
        kill -KILL $pids 2>/dev/null || true
    fi
    # Do this even if gor exited on TERM; its mpv may already have PPID 1.
    stop_tracked_mpv
    for ((attempt = 0; attempt < 10; attempt++)); do
        pids=$(gor_pids)
        [ -n "$pids" ] || return 0
        sleep 0.2
    done
    echo "      gor is still running; refusing bundle replacement/launch" >&2
    return 1
}
stop_running_gor
if [ "$clean_build" = true ]; then
    rm -rf "$project_root/.build"
fi

# ── whisper-live (optional) ────────────────────────────────────────────────────
if [ "$build_whisper" = true ]; then
    next_step whisper-live; echo "building whisper-live..."
    if [ ! -d "$whisper_src_dir" ]; then
        echo "      ✗ whisper_src_dir not found: $whisper_src_dir"
        echo "        (edit whisper_src_dir near the top of this script if it moved)"
        exit 1
    fi
    whisper_build_log=$(mktemp /tmp/gor-whisper-build.XXXXXX)
    if ! (cd "$whisper_src_dir" && cmake --build build --target whisper-live) \
        > "$whisper_build_log" 2>&1; then
        append_direct_log "$whisper_build_log"
        echo "      ✗ whisper-live build failed — see /tmp/gor_direct.log"
        exit 1
    fi
    append_direct_log "$whisper_build_log"
    whisper_bin="$whisper_src_dir/build/bin/whisper-live"
    whisper_dest="$project_root/Resources/vendor/whisper/whisper-live"
    if [ ! -f "$whisper_bin" ]; then
        echo "      ✗ build reported success but binary missing: $whisper_bin"
        exit 1
    fi
    cp "$whisper_bin" "$whisper_dest"
    echo "      done → $whisper_dest"
fi

# v2.2.18: Diag now lives in AppDelegate.swift. Remove only the known
# delivered standalone copy; an unknown local edit must not be overwritten.
old_diag="$project_root/Sources/gor/Diag.swift"
if [ -f "$old_diag" ]; then
    old_diag_hash=$(shasum -a 256 "$old_diag" | awk '{print $1}')
    case "$old_diag_hash" in
        8a9a6f81ce0c8097ae4bf209fa6e1e53d3de83c9d259230013f5e3363a5bd015|7c94f0da803ad4958d1b822658eb678f8399afb20cf18eff9adcf746abaebb14)
            rm "$old_diag" ;;
        *) echo 'unexpected standalone Diag.swift: preserving local file; resolve duplicate Diag before building' >&2; exit 1 ;;
    esac
fi

# GOR_SOURCE_SNAPSHOT_BEGIN
source_snapshot=$(mktemp /tmp/gor-source-snapshot.XXXXXX)
/usr/bin/python3 - "$project_root" "$source_snapshot" <<'PY_SOURCE'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
paths = [root / 'Package.swift', root / 'build.sh'] + sorted((root / 'Sources/gor').rglob('*.swift'))
if len(paths) < 3:
    raise SystemExit('No Swift sources found; refusing build')
records = {}
for path in paths:
    if path.is_symlink() or not path.is_file():
        raise SystemExit('Non-regular build input: ' + str(path))
    records[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
pathlib.Path(sys.argv[2]).write_text(json.dumps(records, indent=2, sort_keys=True) + '\n')
print('      source snapshot sha256: ' + hashlib.sha256(pathlib.Path(sys.argv[2]).read_bytes()).hexdigest())
PY_SOURCE
# GOR_SOURCE_SNAPSHOT_END
# ── swift build — touches bundle only on success ──────────────────────────────
next_step swift; echo "building..."
build_start=$(date +%s)
# The complete Swift output goes to gor_direct.log in either configuration.
# The optional separate document is only kept when explicitly enabled above.
temporary_build_log=$(mktemp /tmp/gor-swift-build.XXXXXX)
build_log="$temporary_build_log"
# Keep a complete compiler record for validation and the direct log.
# Filtered console lines go to fd 3, so gor_direct gets the full compiler
# block once, not a duplicate of the console progress lines.
# pipefail makes an early Swift exit a failure even if the output filter exits 0.
set -o pipefail
exec 6>&3
if [ "$separate_build_log" = true ]; then exec 6>&4; fi
# GOR_SWIFT_RESULT_BEGIN
# Preserve the compiler's status independently of presentation filtering.
# --product emits "Build of product 'gor' complete!", not "Build complete".
if swift build --package-path "$project_root" --scratch-path "$build_dir" -c debug --product "$app_name" > "$build_log" 2>&1; then
    swift_status=0
else
    swift_status=$?
fi
append_direct_log "$build_log"
if [ "$show_warnings" = true ] || [ "$swift_status" -ne 0 ]; then
    cat "$build_log" >&6
else
    grep -E 'error:|Build complete|Build of product .* complete!' "$build_log" >&6 || true
fi
build_end=$(date +%s)
build_elapsed=$((build_end - build_start))
if [ "$swift_status" -ne 0 ]; then
    echo "      swift build failed (status=$swift_status) - previous bundle preserved" >&2
    exit "$swift_status"
fi
# Successful exit is authoritative; resolved product existence, executable
# type and source-input equality are independently checked below.
# GOR_SWIFT_RESULT_END
# GOR_PRODUCT_PATH_BEGIN
bin_dir=$(swift build --package-path "$project_root" --scratch-path "$build_dir" -c debug --product "$app_name" --show-bin-path) || exit 1
debug_bin="$bin_dir/$app_name"
/usr/bin/python3 - "$project_root" "$source_snapshot" "$debug_bin" "$build_dir" <<'PY_PRODUCT'
import hashlib, json, os, pathlib, sys
root, snap, product, scratch = map(pathlib.Path, sys.argv[1:])
expected = json.loads(snap.read_text())
paths = [root / 'Package.swift', root / 'build.sh'] + sorted((root / 'Sources/gor').rglob('*.swift'))
actual = {}
for path in paths:
    if path.is_symlink() or not path.is_file():
        raise SystemExit('Build input changed type during compilation: ' + str(path))
    actual[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
if actual != expected:
    raise SystemExit('Build inputs changed during compilation; installed app unchanged')
if not product.is_file() or product.is_symlink() or not os.access(product, os.X_OK):
    raise SystemExit('Missing/non-regular/non-executable SwiftPM product: ' + str(product))
if os.path.commonpath([str(product.resolve()), str(scratch.resolve())]) != str(scratch.resolve()):
    raise SystemExit('SwiftPM product lies outside this project build directory')
print('      SwiftPM product: ' + str(product.resolve()))
print('      unsigned product sha256: ' + hashlib.sha256(product.read_bytes()).hexdigest())
PY_PRODUCT
# GOR_PRODUCT_PATH_END
echo "      done (${build_elapsed}s swift)"

# ── bundle ────────────────────────────────────────────────────────────────────
# Clone the last *completed* app into an isolated staging bundle. The -c
# request is APFS clone-on-write on macOS; report fallback rather than hiding
# a full ditto copy. The installed app is never edited.
clone_started=$(date +%s)
rm -rf "$staged_bundle"
clone_mode=fresh
if [ -d "$app_bundle" ]; then
    if cp -cpR "$app_bundle" "$staged_bundle" 2>/dev/null; then
        clone_mode=cp-clone-requested
    else
        rm -rf "$staged_bundle"
        ditto "$app_bundle" "$staged_bundle"
        clone_mode=ditto-fallback
    fi
fi
mkdir -p "$dest" "$res"
# A cloned previous bundle must not retain an old helper on raw fallback.
rm -f "$dest/gor-log-writer"
if [ "$log_writer_enabled" = true ]; then
    cp "$log_writer" "$dest/gor-log-writer"
fi
printf '{"timestamp":%s,"cpu_info":%s}\n' "$log_timestamp" "$log_cpu_info" > "$res/gor-log-config.json"
# Remove any helper retained by the previous bundle clone when disabled.
case "$exit_log_zip" in true|false) ;; *) echo 'exit_log_zip must be true or false' >&2; exit 2;; esac
rm -f "$res/gor-session-log-helper.py"
if [ "$exit_log_zip" = true ]; then
# Install the detached exit watcher before bundle signing; do not collect here.
cat > "$res/gor-session-log-helper.py" <<'GOR_SESSION_HELPER'
#!/usr/bin/python3
# Detached post-exit evidence collector. No source or credentials archived.
import datetime, hashlib, json, os, pathlib, subprocess, sys, tempfile, time, zipfile
STATE = pathlib.Path.home() / 'Library/Application Support/gor/log-sessions'
def identity(pid):
    try:
        return subprocess.check_output(['/bin/ps', '-p', str(pid), '-o', 'lstart='], stderr=subprocess.DEVNULL).decode().strip()
    except subprocess.CalledProcessError:
        return ''
def archive(record, reason):
    sources = [(pathlib.Path('/tmp')/n,n) for n in ['gor_diag.log','gor_direct.log','gor_sample.txt','wt_full.log']]
    config=pathlib.Path(record['config'])
    sources += [(config/n,n) for n in ['photon-grain-size.log','photon-grain-doc.log']]
    if pathlib.Path('/tmp/gor_build.log').is_file():sources.append((pathlib.Path('/tmp/gor_build.log'),'gor_build.log'))
    sources += [(pathlib.Path(record['bundle'])/'Contents/Resources/gor-build-manifest.json','gor-build-manifest.json')]
    sources += [(pathlib.Path(record['bundle'])/'Contents/Resources/gor-swift-build-manifest.json','gor-swift-build-manifest.json')]
    sources += [(pathlib.Path.home()/'Library/Logs/gor/quit-debug.log','gor-quit-debug.log')]
    status=['SESSION '+record['id']+' '+reason, 'Logs are shared paths; recovery may contain mixed or missing evidence.']
    entries={}
    for path,name in sources:
        try: entries[name]=path.read_bytes()
        except OSError: status.append('MISSING '+name)
    hashes=[]
    try:
        scripts=config/'scripts'
        for path in sorted(scripts.rglob('*.lua')):
            if not path.is_file():continue
            name=path.relative_to(scripts).as_posix()
            try: hashes.append(hashlib.sha256(path.read_bytes()).hexdigest()+'\t'+name)
            except OSError:status.append('MISSING installed-script-hash '+name)
        if not hashes:status.append('MISSING installed scripts/*.lua')
    except OSError:status.append('MISSING installed scripts/*.lua')
    entries['installed-script-sha256.txt']=('\n'.join(hashes)+'\n').encode()
    entries['collection-status.txt']=('\n'.join(status)+'\n').encode()
    stamp=datetime.datetime.now().strftime('%y%m%d-%H%M%S')
    output=pathlib.Path('/tmp')/(stamp+'-gor-log.zip')
    while output.exists():
        time.sleep(1);stamp=datetime.datetime.now().strftime('%y%m%d-%H%M%S');output=pathlib.Path('/tmp')/(stamp+'-gor-log.zip')
    fd,temp=tempfile.mkstemp(prefix='.gor-log-',suffix='.zip',dir='/tmp');os.close(fd)
    try:
        with zipfile.ZipFile(temp,'w',zipfile.ZIP_DEFLATED) as z:
            for name,data in entries.items():z.writestr(name,data)
        with zipfile.ZipFile(temp) as z:
            if z.testzip() is not None:raise OSError('archive CRC failure')
        os.rename(temp,output)
    finally:
        if os.path.exists(temp):os.unlink(temp)
    return str(output)
def finish(path,reason):
    # Atomic claim excludes simultaneous watcher/recovery archive duplication.
    claim=path.with_suffix('.collecting')
    try:path.rename(claim)
    except FileNotFoundError:return
    try:
        record=json.loads(claim.read_text());output=archive(record,reason)
        print(output,flush=True);claim.unlink()
    except Exception:
        if claim.exists():claim.rename(path)
        raise
if sys.argv[1]=='arm':
    pid=int(sys.argv[2]);bundle=sys.argv[3];config=sys.argv[4]
    STATE.mkdir(parents=True,exist_ok=True)
    # A .collecting left by power loss is recoverable on next launch.
    for claim in STATE.glob('*.collecting'):
        try:
            r=json.loads(claim.read_text())
            if identity(r['pid'])!=r['identity'] and time.time()-claim.stat().st_mtime>60:claim.rename(claim.with_suffix('.json'))
        except (OSError,ValueError):pass
    for pending in STATE.glob('*.json'):
        try:
            r=json.loads(pending.read_text())
            if identity(r['pid'])!=r['identity']:finish(pending,'next-launch-recovery')
        except (OSError,ValueError):pass
    start=identity(pid)
    if not start:raise SystemExit('cannot bind owner process')
    record={'id':str(pid)+'-'+hashlib.sha256(start.encode()).hexdigest()[:16],'pid':pid,'identity':start,'bundle':bundle,'config':config}
    pending=STATE/(record['id']+'.json')
    try:
        fd=os.open(pending,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    except FileExistsError:
        raise SystemExit(0)
    with os.fdopen(fd,'w') as f:json.dump(record,f)
    subprocess.Popen(['/usr/bin/python3',__file__,'watch',str(pending)],start_new_session=True,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,close_fds=True)
elif sys.argv[1]=='watch':
    pending=pathlib.Path(sys.argv[2]);record=json.loads(pending.read_text())
    while identity(record['pid'])==record['identity']:time.sleep(1)
    # Give subprocess log flushes a bounded grace period after owner exit.
    time.sleep(1)
    finish(pending,'owner-process-exited')
else:raise SystemExit('unknown helper mode')
GOR_SESSION_HELPER
fi

# Each installed and backup app retains its own immutable external snapshot.
# Do not repoint a shared vendor tree: .previous must remain independently usable.
# Older snapshots remain on disk for rollback; remove them only after both
# installed and backup apps no longer point at them.
dev_vendor_snapshot=""
dev_vendor_committed=false
if [ "$vendor_layout" = linked-dev ]; then
    dev_vendor_snapshot="$project_root/.gor-vendor-builds/vendor-dev-$(date +%s)-$$"
    mkdir -p "$dev_vendor_snapshot"
    # Source files are copied into a fresh snapshot. Re-signing changed leaves
    # never mutates the installed app or its .previous backup via clone links.
    if ! cp -cpR "$project_root/Resources/vendor/." "$dev_vendor_snapshot/" 2>/dev/null; then
        rm -rf "$dev_vendor_snapshot"
        mkdir -p "$dev_vendor_snapshot"
        if ! ditto "$project_root/Resources/vendor" "$dev_vendor_snapshot"; then
            echo "failed to copy vendor source into snapshot" >&2
            exit 1
        fi
    fi
    rm -rf "$res/vendor"
    ln -s "$dev_vendor_snapshot" "$res/vendor"
elif [ -L "$res/vendor" ]; then
    # Switching back from linked-dev must materialize the vendor directory
    # before the sealed build; never seal the old external symlink.
    previous_vendor="$(readlink "$res/vendor")"
    case "$previous_vendor" in
        "$project_root/.gor-vendor-builds/"*) ;;
        *) echo "unexpected previous vendor link: $previous_vendor" >&2; exit 1 ;;
    esac
    test -d "$previous_vendor" || { echo "previous vendor snapshot missing" >&2; exit 1; }
    rm "$res/vendor"
    mkdir -p "$res/vendor"
    if ! cp -cpR "$previous_vendor/." "$res/vendor/"; then
        echo "failed to materialize vendor for sealed build" >&2
        exit 1
    fi
fi
echo "      timing: stage ${clone_mode} $(( $(date +%s) - clone_started ))s"

next_step resources; echo "copying resources..."
# This candidate's new extractor closure is staged/signed only in sealed mode.
# Never mutate a shared linked-dev vendor snapshot while signing its files.
if [ -d "$project_root/Resources/vendor/yt-dlp-standalone" ] && [ "$vendor_layout" != sealed ]; then
    echo 'yt-dlp standalone candidate requires sealed vendor layout' >&2
    exit 1
fi

for required in \
    "$project_root/Resources/vendor/mpv/bin/mpv" \
    "$project_root/Resources/vendor/node/node" \
    "$project_root/Resources/vendor/mega_relay/mega_relay.mjs" \
    "$project_root/Resources/vendor/mega_relay/node_modules/megajs/dist/main.node-es.mjs" \
    "$project_root/Resources/vendor/webtorrent-cli/node_modules/webtorrent/index.js"; do
    if [ ! -f "$required" ]; then
        echo "      ✗ required bundled resource missing: $required" >&2
        exit 1
    fi
done

# codesign changes Mach-O bytes, so a plain source→staging rsync would undo
# signatures each build. Exclude signable paths, compare their *source* hashes
# against the manifest sealed in the previous app, then copy/sign only changes.
# v2 invalidates the first incremental build's vendor signatures: those were
# accidentally signed with hardened runtime and broke Homebrew dylib loading.
manifest_name=".gor-vendor-source-sha256-v2"
old_manifest="$app_bundle/Contents/Resources/$manifest_name"
new_manifest="$res/$manifest_name"
metadata_name=".gor-vendor-source-stat-v2"
old_metadata="$app_bundle/Contents/Resources/$metadata_name"
new_metadata="$res/$metadata_name"
exclude_file=$(mktemp "${TMPDIR:-/tmp}/gor-vendor-exclude.XXXXXX")
manifest_tmp=$(mktemp "${TMPDIR:-/tmp}/gor-vendor-manifest.XXXXXX")
metadata_tmp=$(mktemp "${TMPDIR:-/tmp}/gor-vendor-stat.XXXXXX")
: > "$exclude_file"
: > "$manifest_tmp"
: > "$metadata_tmp"

# Reuse only against a verified previous app and matching source. A change
# in signing policy requires GOR_RESIGN_VENDOR=1 for one build. The final
# deep verification checks the staged nested code before swap.
reuse_signed=false
if [ "$signing_enabled" = true ] && [ "${GOR_RESIGN_VENDOR:-0}" != 1 ] && \
   [ -f "$old_manifest" ] && [ -d "$app_bundle" ] && \
   [ -d "$app_bundle/Contents/Resources/vendor" ] && \
   codesign --verify --strict "$app_bundle" >/dev/null 2>&1; then
    reuse_signed=true
    # A linked-dev outer seal covers only the path of its external vendor.
    # Check that snapshot's signed leaves before trusting the old manifest.
    if [ -L "$app_bundle/Contents/Resources/vendor" ]; then
        while IFS= read -r -d '' leaf; do
            if ! codesign --verify --strict "$leaf" >/dev/null 2>&1; then
                reuse_signed=false
                break
            fi
        done < <(find "$app_bundle/Contents/Resources/vendor/" -type f \
            \( -name mpv -o -name ffmpeg -o -name gifsicle -o -name '*.dylib' \
               -o -name mus2 -o -name node -o -name chrome-headless-shell \) -print0)
    fi
fi
changed_signed=()
signable_extra=()
if [ "$vendor_layout" = linked-dev ]; then signable_extra=(-o -name node); fi
verified_skipped=0
hash_started=$(date +%s)
while IFS= read -r -d '' source_file; do
    rel=${source_file#"$project_root/Resources/vendor/"}
    # Extend the existing incremental source/signature manifest ONLY for
    # actual Mach-O leaves in the official yt-dlp onedir subtree. Data/EJS
    # stay in normal rsync, unchanged; every code leaf follows reuse/deepverify.
    case "$rel" in
        yt-dlp-standalone/*)
            if ! /usr/bin/file -b "$source_file" | /usr/bin/grep -q 'Mach-O'; then
                continue
            fi ;;
    esac
    # The manifest/exclude formats cannot safely encode embedded newlines or tabs.
    case "$rel" in *$'\n'*|*$'\t'*) echo "unsupported vendor filename: $rel" >&2; exit 1;; esac
    printf '/%s\n' "$rel" >> "$exclude_file"
    # Size, mtime and ctime are cheap to check. A normal changed source gets
    # a new ctime even when a tool preserves the mtime. On an old manifest or
    # a changed stat tuple, compute the real hash to decide whether to resign.
    source_stat=$(stat -f '%z:%m:%c' "$source_file")
    old_stat=""
    previous_hash=""
    if [ "$reuse_signed" = true ]; then
        previous_hash=$(awk -F '\t' -v f="$rel" '$2 == f {print $1; exit}' "$old_manifest")
        if [ -f "$old_metadata" ]; then
            old_stat=$(awk -F '\t' -v f="$rel" '$2 == f {print $1; exit}' "$old_metadata")
        fi
    fi
    if [ "$reuse_signed" = true ] && [ -n "$previous_hash" ] && \
       [ -n "$old_stat" ] && [ "$source_stat" = "$old_stat" ] && \
       [ -f "$res/vendor/$rel" ]; then
        hash=$previous_hash
    else
        hash=$(shasum -a 256 "$source_file" | awk '{print $1}')
    fi
    printf '%s\t%s\n' "$hash" "$rel" >> "$manifest_tmp"
    printf '%s\t%s\n' "$source_stat" "$rel" >> "$metadata_tmp"
    if [ "$reuse_signed" = true ] && [ "${GOR_RESIGN_VENDOR:-0}" != 1 ] && \
       [ "$hash" = "$previous_hash" ] && [ -f "$res/vendor/$rel" ]; then
        verified_skipped=$((verified_skipped + 1))
        # Final deep verify covers these reused signatures as a set.
    else
        changed_signed+=("$rel")
    fi
done < <(find "$project_root/Resources/vendor" -type f \
    \( -name mpv -o -name ffmpeg -o -name gifsicle -o -name '*.dylib' -o -name mus2 \
       -o -path "$project_root/Resources/vendor/yt-dlp-standalone/*" \
       "${signable_extra[@]}" \) -print0)
echo "      timing: vendor stat + conditional hash $(( $(date +%s) - hash_started ))s (${verified_skipped} candidates, ${#changed_signed[@]} changed)"

rsync_started=$(date +%s)
if [ "$vendor_layout" = linked-dev ]; then
    # Restore only byte-identical signed leaves from the previous bundle;
    # source copying above would otherwise replace them with unsigned files.
    if [ "$reuse_signed" = true ]; then
        while IFS=$'\t' read -r _hash rel; do
            [ -n "$rel" ] || continue
            is_changed=false
            for changed in "${changed_signed[@]}"; do
                if [ "$changed" = "$rel" ]; then is_changed=true; break; fi
            done
            if [ "$is_changed" = true ]; then continue; fi
            if [ -f "$app_bundle/Contents/Resources/vendor/$rel" ]; then
                cp -p "$app_bundle/Contents/Resources/vendor/$rel" "$res/vendor/$rel"
            fi
        done < "$manifest_tmp"
    fi
else
    rsync -a --delete --exclude-from="$exclude_file" \
        "$project_root/Resources/vendor/" "$res/vendor/"
fi
echo "      timing: vendor rsync $(( $(date +%s) - rsync_started ))s"

# Repair only the measured OpenSSL edge in the staged node tree. Never edit
# the source vendor, installed app, or backup. mpv/libass are outside this gate.
prepare_node_closure() {
    local node_root="$1" mode="${2:-verify}" node_ssl node_crypto old_crypto ssl_deps leaf deps archs
    local leaf_list
    local repaired_leaves=()
    local vendor_anchor node_resolved expected_anchor link_list
    # Allow only the build-created linked-dev snapshot as the vendor root.
    if [ "$vendor_layout" = linked-dev ]; then
        test -n "$dev_vendor_snapshot" || return 1
        expected_anchor=$(cd "$dev_vendor_snapshot" && pwd -P) || return 1
    else
        test ! -L "$res/vendor" || { echo 'node closure: unexpected vendor symlink' >&2; return 1; }
        expected_anchor=$(cd "$res/vendor" && pwd -P) || return 1
    fi
    vendor_anchor=$(cd "$res/vendor" && pwd -P) || return 1
    test "$vendor_anchor" = "$expected_anchor" || { echo 'node closure: vendor escaped staging anchor' >&2; return 1; }
    test ! -L "$vendor_anchor/node" || { echo 'node closure: node root symlink rejected' >&2; return 1; }
    node_resolved=$(cd "$vendor_anchor/node" && pwd -P) || return 1
    test "$node_resolved" = "$vendor_anchor/node" || return 1
    node_root="$node_resolved"
    # Conservative: reject every nested symlink before editing any leaf.
    # This may reject benign aliases; never follow an out-of-tree leaf.
    link_list=$(mktemp "${TMPDIR:-/tmp}/gor-node-links.XXXXXX") || return 1
    if ! find "$node_root" -type l -print > "$link_list"; then rm -f "$link_list"; return 1; fi
    if [ -s "$link_list" ]; then
        echo 'node closure: nested symlinks rejected before mutation' >&2
        cat "$link_list" >&2; rm -f "$link_list"; return 1
    fi
    rm -f "$link_list"
    node_ssl="$node_root/lib/libssl.3.dylib"
    node_crypto="$node_root/lib/libcrypto.3.dylib"
    for leaf in "$node_root/node" "$node_ssl" "$node_crypto"; do
        test -f "$leaf" || { echo "node closure: missing required leaf: $leaf" >&2; return 1; }
    done
    leaf_list=$(mktemp "${TMPDIR:-/tmp}/gor-node-closure.XXXXXX") || return 1
    # Inspect every staged regular file; do not assume only .dylib files are Mach-O.
    if ! find "$node_root" -type f -print0 > "$leaf_list"; then
        rm -f "$leaf_list"; return 1
    fi
    while IFS= read -r -d '' leaf; do
        local kind
        kind=$(file -b "$leaf") || { rm -f "$leaf_list"; return 1; }
        case "$kind" in
            *Mach-O*) ;;
            *)
                if [ "$leaf" = "$node_root/node" ] || [ "$leaf" = "$node_ssl" ] || [ "$leaf" = "$node_crypto" ]; then
                    echo "node closure: required leaf is not Mach-O: $leaf" >&2
                    rm -f "$leaf_list"; return 1
                fi
                continue ;;
        esac
        archs=$(lipo -archs "$leaf") || { rm -f "$leaf_list"; return 1; }
        test "$archs" = arm64 || { echo "node closure: non-thin-arm64 leaf: $leaf" >&2; rm -f "$leaf_list"; return 1; }
        deps=$(otool -L "$leaf") || { rm -f "$leaf_list"; return 1; }
        if [ "$mode" = repair ]; then
            local load_paths id_output install_id dep base target replacement changed paths_file
            changed=false
            install_id=''
            # Only dylibs have LC_ID_DYLIB. Query it separately; never infer it
            # from an abbreviated -L list or matching dependency basename.
            case "$kind" in
                *dynamically\ linked\ shared\ library*)
                    id_output=$(otool -D "$leaf") || { rm -f "$leaf_list"; return 1; }
                    install_id=$(printf '%s\n' "$id_output" | tail -n +2 | sed 's/^[[:space:]]*//')
                    test -n "$install_id" || { echo "node closure: missing dylib ID: $leaf" >&2; rm -f "$leaf_list"; return 1; }
                    case "$install_id" in
                        /opt/homebrew/*|/usr/local/*|/Users/*)
                            base=${leaf##*/}
                            # Defer ID mutation until this leaf's dependency edits succeed.
                            : ;;
                    esac ;;
            esac
            paths_file=$(mktemp "${TMPDIR:-/tmp}/gor-node-paths.XXXXXX") || { rm -f "$leaf_list"; return 1; }
            # Preserve embedded spaces in install names; strip the version suffix.
            printf '%s\n' "$deps" | sed '1d;s/^[[:space:]]*//;s/ (compatibility version.*$//' > "$paths_file"
            while IFS= read -r dep; do
                test -n "$dep" || continue
                test "$dep" != "$install_id" || continue
                case "$dep" in
                    /opt/homebrew/*|/usr/local/*|/Users/*)
                        base=${dep##*/}
                        target="$node_root/lib/$base"
                        if [ ! -f "$target" ] || [ -L "$target" ]; then
                            echo "node closure: unvendored dependency: $leaf -> $dep" >&2
                            rm -f "$paths_file" "$leaf_list"; return 1
                        fi
                        # Relative to this loader, not the executable. Only the
                        # measured lib/ and root-node layouts are rewritten.
                        case "$leaf" in
                            "$node_root/lib/"*)
                                test "$(dirname "$leaf")" = "$node_root/lib" || { rm -f "$paths_file" "$leaf_list"; return 1; }
                                replacement="@loader_path/$base" ;;
                            "$node_root/node") replacement="@loader_path/lib/$base" ;;
                            *) echo "node closure: unsupported loader layout: $leaf" >&2
                               rm -f "$paths_file" "$leaf_list"; return 1 ;;
                        esac
                        install_name_tool -change "$dep" "$replacement" "$leaf" || { rm -f "$paths_file" "$leaf_list"; return 1; }
                        changed=true ;;
                esac
            done < "$paths_file"
            rm -f "$paths_file"
            case "$install_id" in
                /opt/homebrew/*|/usr/local/*|/Users/*)
                    install_name_tool -id "@rpath/${leaf##*/}" "$leaf" || { rm -f "$leaf_list"; return 1; }
                    changed=true ;;
            esac
            if [ "$changed" = true ]; then repaired_leaves+=("$leaf"); fi
            # Measure again after edits; stale pre-edit output cannot pass gate.
            deps=$(otool -L "$leaf") || { rm -f "$leaf_list"; return 1; }
        fi
        local gate_id_output=''
        case "$kind" in
            *dynamically\ linked\ shared\ library*)
                gate_id_output=$(otool -D "$leaf") || { rm -f "$leaf_list"; return 1; }
                test -n "$(printf '%s\n' "$gate_id_output" | tail -n +2)" || { rm -f "$leaf_list"; return 1; }
                # Both outputs have a header. Join ID rows after the -L rows.
                deps="$deps
$(printf '%s\n' "$gate_id_output" | tail -n +2)" ;;
        esac
        # IDs/imports must be relative dyld paths or Apple system paths only.
        if ! printf '%s\n' "$deps" | awk -v leaf="$leaf" '
            NR>1 && NF {
                path=$0; sub(/^[ \t]*/, "", path); sub(/ \(compatibility version.*$/, "", path)
                if (path !~ /^@rpath\// && path !~ /^@loader_path\// &&
                    path !~ /^@executable_path\// && path !~ /^\/usr\/lib\// &&
                    path !~ /^\/System\/Library\//) {
                    print "node closure: forbidden path in " leaf ": " path > "/dev/stderr"
                    failed=1
                }
                count++
            }
            END { if (count==0 || failed) exit 1 }
        '; then
            rm -f "$leaf_list"; return 1
        fi
    done < "$leaf_list"
    rm -f "$leaf_list"
    # Sign only after every dependency/ID rewrite completed successfully.
    for leaf in "${repaired_leaves[@]}"; do
        codesign --force --preserve-metadata=entitlements,flags --sign - "$leaf" || return 1
        codesign --verify --strict "$leaf" || return 1
    done
}


# The updater stages a complete Google-signed Chromium tree outside the source
# vendor directory. Inject only into the temporary app being built, then seal
# that app normally. Never change the running bundle or the project source.
chromium_stage="$build_dir/chromium-update"
chromium_stage_active=false
if [ -d "$chromium_stage" ]; then
    staged_rel="$(cat "$chromium_stage/binary-relative-path.txt")"
    case "$staged_rel" in
        chrome-headless-shell|*/chrome-headless-shell) ;;
        *) echo "invalid chromium stage path" >&2; exit 1 ;;
    esac
    case "$staged_rel" in
        ../*|*/../*|/*) echo "invalid chromium stage path" >&2; exit 1 ;;
    esac
    staged_dir="$(dirname "$staged_rel")"
    staged_binary="$chromium_stage/payload/$staged_rel"
    test -f "$staged_binary" || { echo "incomplete chromium stage" >&2; exit 1; }
    # Only replace the tree containing the existing browser, never guess a path.
    test -f "$res/vendor/chromium/$staged_rel" || { echo "chromium bundled path differs from stage" >&2; exit 1; }
    staged_version="$(cat "$chromium_stage/version.txt")"
    actual_version="$("$staged_binary" --version 2>/dev/null)"
    case "$actual_version" in
        *"$staged_version") ;;
        *) echo "staged chromium version mismatch" >&2; exit 1 ;;
    esac
    if [ "$staged_dir" = . ]; then
        echo "root-level chromium stage unsupported" >&2
        exit 1
    fi
    rm -rf "$res/vendor/chromium/$staged_dir"
    mkdir -p "$res/vendor/chromium/$staged_dir"
    cp -R "$chromium_stage/payload/$staged_dir/." "$res/vendor/chromium/$staged_dir/"
    chromium_stage_active=true
    echo "      chromium: staged $staged_version for signed build"
fi

# Copy all source binaries on --no-sign, rather than retaining old signatures.
if [ "$signing_enabled" != true ]; then
    changed_signed=()
    while IFS= read -r -d '' source_file; do
        rel=${source_file#"$project_root/Resources/vendor/"}
        case "$rel" in
            yt-dlp-standalone/*)
                if ! /usr/bin/file -b "$source_file" | /usr/bin/grep -q 'Mach-O'; then
                    continue
                fi ;;
        esac
        changed_signed+=("$rel")
    done < <(find "$project_root/Resources/vendor" -type f \
        \( -name mpv -o -name ffmpeg -o -name gifsicle -o -name '*.dylib' -o -name mus2 \
           -o -path "$project_root/Resources/vendor/yt-dlp-standalone/*" \) -print0)
fi
for rel in "${changed_signed[@]}"; do
    mkdir -p "$(dirname "$res/vendor/$rel")"
    cp -p "$project_root/Resources/vendor/$rel" "$res/vendor/$rel"
    chmod u+w "$res/vendor/$rel"
done
# Onedir must be complete before launch selection; raw source checks happen
# before signing changes Mach-O bytes. No partial executable+Python sentinel.
if [ -d "$res/vendor/yt-dlp-standalone" ]; then
    /usr/bin/python3 - "$project_root/Resources/vendor/yt-dlp-standalone" <<'PY_YTDLP_CLOSURE'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]); manifest=root/'GOR-CLOSURE.json'
if not manifest.is_file(): raise SystemExit('yt-dlp closure manifest missing')
records=json.loads(manifest.read_text())
actual={str(p.relative_to(root)) for p in root.rglob('*') if p.is_file() and p.name!='GOR-CLOSURE.json'}
if set(records)!=actual: raise SystemExit('yt-dlp closure files differ')
for rel,sha in records.items():
    p=root/rel
    if p.is_symlink() or hashlib.sha256(p.read_bytes()).hexdigest()!=sha:
        raise SystemExit('yt-dlp closure hash differs: '+rel)
PY_YTDLP_CLOSURE
fi
# An obsolete signed file, excluded from rsync on older builds, must not linger.
# The current exclude list names only current source files, so --delete above
# removes old ones automatically.
fonts_started=$(date +%s)
if [ -d "$project_root/Resources/fonts" ]; then
    rsync -a --delete "$project_root/Resources/fonts/" "$res/fonts/"
else
    rm -rf "$res/fonts"
fi
echo "      timing: fonts rsync $(( $(date +%s) - fonts_started ))s"
if find "${dev_vendor_snapshot:-$res/vendor}" "$res/fonts" -type l -print 2>/dev/null | grep -q .; then
    echo "      ✗ vendor contains symlinks; inspect and replace with bundled files" >&2
    exit 1
fi
# v2.2.17: only executable Lua belongs in mpv's auto-loaded scripts tree.
# Work on the new staging tree/snapshot, never the source or installed app.
script_root="$res/vendor/mpv/scripts"
test -d "$script_root" || { echo 'mpv scripts directory missing' >&2; exit 1; }
while IFS= read -r -d '' script; do
    case "$script" in *.lua) ;; *) rm -f "$script" ;; esac
done < <(find "$script_root" \( -type f -o -type l \) -print0)
# Manifest covers all staged Lua scripts before bundle signing. JSON escaping
# is handled by Python; build fails rather than shipping an absent manifest.
/usr/bin/python3 - "$script_root" "$res/gor-build-manifest.json" "$project_root/Resources/vendor/mpv/scripts" <<'PY'
import datetime, hashlib, json, pathlib, stat, sys
root = pathlib.Path(sys.argv[1])
source = pathlib.Path(sys.argv[3])
required = ['photon.lua', 'photon-common.lua', 'photon-grain.lua', 'photon-hud.lua', 'autoload.lua', 'photon-sharp.lua']
for name in required:
    original, staged = source / name, root / name
    if not all(stat.S_ISREG(p.lstat().st_mode) for p in (original, staged)):
        raise SystemExit('required Lua missing/non-regular: ' + name)
    if hashlib.sha256(original.read_bytes()).digest() != hashlib.sha256(staged.read_bytes()).digest():
        raise SystemExit('staged Lua SHA256 differs from source: ' + name)
scripts = {}
for path in sorted(root.rglob('*.lua')):
    if not stat.S_ISREG(path.lstat().st_mode):
        raise SystemExit('staged Lua non-regular: ' + str(path))
    scripts[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
if not scripts:
    raise SystemExit('no Lua scripts for build manifest')
manifest = {'version': '2.2.22', 'build_time': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'scripts': scripts}
pathlib.Path(sys.argv[2]).write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
PY

prepare_node_closure "$res/vendor/node" repair
entitlements_path="$project_root/Resources/gor.entitlements"
cp -p "$entitlements_path" "$res/gor.entitlements"
# Even on --no-sign, retain the source-hash record only after signed output;
# otherwise the next signed build must re-sign every vendor binary.
if [ "$signing_enabled" = true ]; then
    cp "$manifest_tmp" "$new_manifest"
    cp "$metadata_tmp" "$new_metadata"
else
    rm -f "$new_manifest" "$new_metadata"
fi
echo "      done (${#changed_signed[@]} vendor binaries changed)"

next_step bundle; echo "creating bundle..."
cp "$debug_bin" "$dest/$app_name"
chmod u+w "$dest/$app_name"
# Source custody is sealed into the app. This records the pre-sign executable;
# codesign may change its bytes. The signed executable hash is logged below.
/usr/bin/python3 - "$source_snapshot" "$debug_bin" "$dest/$app_name" "$res/gor-swift-build-manifest.json" <<'PY_MANIFEST'
import hashlib, json, pathlib, sys
snapshot, product, staged, output = map(pathlib.Path, sys.argv[1:])
a, b = product.read_bytes(), staged.read_bytes()
if a != b:
    raise SystemExit('Staged executable differs from SwiftPM product; refusing install')
record = {'schema': 1, 'build_inputs': json.loads(snapshot.read_text()), 'swiftpm_product': str(product.resolve()), 'unsigned_executable_sha256': hashlib.sha256(a).hexdigest()}
output.write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
PY_MANIFEST

# GOR_BUILD_ID_BEGIN
# Build identity is derived from the exact verified compile-input manifest,
# not an absent parent kit file or an unrelated checkout's git HEAD.
/usr/bin/python3 - "$source_snapshot" "$res/build-id.txt" <<'PY_BUILD_ID'
import hashlib, pathlib, sys
snapshot, output = map(pathlib.Path, sys.argv[1:])
identity = hashlib.sha256(snapshot.read_bytes()).hexdigest()
output.write_text('commit=' + identity + '\nidentity_kind=source-manifest-sha256\n')
assert output.read_text().splitlines()[0] == 'commit=' + identity
print('      build-id (source manifest): ' + identity)
PY_BUILD_ID
# GOR_BUILD_ID_END

if [ -f "$icon_source" ]; then
    src_mod=$(stat -f "%m" "$icon_source" 2>/dev/null || echo "0")
    cache_mod=$(stat -f "%m" "$icon_cache" 2>/dev/null || echo "0")
    if [ ! -f "$icon_cache" ] || [ "$src_mod" -gt "$cache_mod" ]; then
        iconset="/tmp/gor.iconset"
        mkdir -p "$iconset"
        for s in 16 32 128 256 512; do
            sips -z $s $s "$icon_source" --out "$iconset/icon_${s}x${s}.png" > /dev/null 2>&1
            sips -z $((s*2)) $((s*2)) "$icon_source" --out "$iconset/icon_${s}x${s}@2x.png" > /dev/null 2>&1
        done
        iconutil -c icns "$iconset" -o "$icon_cache" 2>/dev/null
        rm -rf "$iconset"
    fi
    cp "$icon_cache" "$res/AppIcon.icns"
fi

cat > "$staged_bundle/Contents/Info.plist" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$app_name</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>$bundle_id</string>
    <key>CFBundleName</key><string>$app_name</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.4</string>
    <key>LSUIElement</key><true/>
    <key>NSScreenCaptureUsageDescription</key><string>Gor uses screen capture audio to drive dynamic subtitle font weight based on audio levels.</string>
    <key>NSMicrophoneUsageDescription</key><string>Gor reads system audio levels for subtitle animation.</string>
    <key>NSAudioCaptureUsageDescription</key><string>Gor captures player audio levels to animate variable fonts. Audio is processed on this Mac.</string>
    <key>NSCameraUsageDescription</key><string>Gor uses your camera to track head position for VR180 look-around. Video is processed on-device and never recorded or transmitted.</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key><true/>
    </dict>
</dict>
</plist>
PLISTEOF

# ── signing ───────────────────────────────────────────────────────────────────
# A local app should not silently inherit downloaded quarantine attributes.
# Inspect the source and staged bundle, but never alter security policy here.
if [ -n "$(xattr -p com.apple.quarantine "$app_bundle" 2>/dev/null || true)" ]; then
    echo "      note: existing app carries com.apple.quarantine; check its provenance"
fi
if [ -n "$(xattr -p com.apple.quarantine "$staged_bundle" 2>/dev/null || true)" ]; then
    echo "      note: staged app carries com.apple.quarantine; not removing it automatically"
fi
if [ "$signing_enabled" = true ]; then
    next_step signing; echo "signing..."
    vendor_sign_started=$(date +%s)
    for rel in "${changed_signed[@]}"; do
        # Preserve the former vendor posture: ad-hoc WITHOUT hardened runtime.
        # mpv still loads /opt/homebrew libass; runtime validation blocks it.
        case "$rel" in
            yt-dlp-standalone/*) codesign --force --preserve-metadata=entitlements,flags --sign - "$res/vendor/$rel" ;;
            node/*) codesign --force --preserve-metadata=entitlements,flags --sign - "$res/vendor/$rel" ;;
            *) codesign --force --sign - "$res/vendor/$rel" ;;
        esac
    done
    echo "      timing: vendor sign $(( $(date +%s) - vendor_sign_started ))s (${#changed_signed[@]} signed, ${verified_skipped} reused; final verification below)"
    if [ "$chromium_stage_active" = true ]; then
        # Mirror vendor posture: ad-hoc leaf signatures without hardened
        # runtime; MacDev signs the enclosing .app with its stable identity.
        while IFS= read -r -d '' leaf; do
            codesign --force --sign - "$leaf"
        done < <(find "$res/vendor/chromium" -type f \
            \( -name 'chrome-headless-shell' -o -name '*.dylib' \) -print0)
    fi
    outer_sign_started=$(date +%s)
    # Only the app executable, plist and changed resources need a new outer
    # seal. --deep --force here would recurse and defeat binary reuse.
    if codesign --force --options runtime --entitlements "$entitlements_path" --sign "MacDev" "$staged_bundle"; then
        echo "      signed: MacDev"
    else
        if [ "$vendor_layout" = linked-dev ]; then
            echo "MacDev identity unavailable; linked-dev refuses ad-hoc fallback to preserve TCC identity" >&2
            exit 1
        fi
        if [ "$chromium_stage_active" = true ]; then
            echo "MacDev identity unavailable; refusing chromium update and ad-hoc outer signature" >&2
            exit 1
        fi
        echo "Stable MacDev signing failed; refusing an ad-hoc replacement of the app." >&2
        echo "The existing app is unchanged. Signing errors above identify the missing or ambiguous identity." >&2
        exit 1
    fi
    echo "      timing: outer sign $(( $(date +%s) - outer_sign_started ))s"
    verify_started=$(date +%s)
    if [ "$vendor_layout" = linked-dev ]; then
        # The outer seal covers the symlink, not its destination. Verify each
        # signable leaf and the signed Chromium executable explicitly.
        for required_leaf in mpv/bin/mpv node/node; do
            if [ ! -f "$dev_vendor_snapshot/$required_leaf" ]; then
                echo "missing signed vendor leaf: $required_leaf" >&2
                exit 1
            fi
            codesign --verify --strict "$dev_vendor_snapshot/$required_leaf"
        done
        while IFS= read -r -d '' leaf; do
            codesign --verify --strict "$leaf"
        done < <(find "$dev_vendor_snapshot" -type f \
            \( -name mpv -o -name ffmpeg -o -name gifsicle -o -name '*.dylib' \
               -o -name mus2 -o -name node -o -name chrome-headless-shell \) -print0)
        codesign --verify --strict "$staged_bundle"
        echo "      timing: outer + vendor verify $(( $(date +%s) - verify_started ))s (linked-dev)"
    elif [ "$signing_mode" = "distribution" ] || [ "$chromium_stage_active" = true ] || [ "${#changed_signed[@]}" -ne 0 ] || [ "$reuse_signed" != true ]; then
        codesign --verify --deep --strict "$staged_bundle"
        echo "      timing: deep verify $(( $(date +%s) - verify_started ))s (distribution/new vendor)"
    else
        # Dev path: old outer bundle verified before cloning, vendor files were
        # reused, and the newly signed app seal must still verify. This omits
        # only recursive checking of unchanged nested signatures.
        codesign --verify --strict "$staged_bundle"
        echo "      timing: outer verify $(( $(date +%s) - verify_started ))s (vendor unchanged)"
    fi
else
    next_step signing; echo "signing skipped"
    # A cloned app may have a stale signature from a prior signed build.
    rm -rf "$staged_bundle/Contents/_CodeSignature"
fi
# Recheck the final staged prefix/architecture sweep after all signing.
# This is not @rpath resolution or transitive dyld closure proof.
prepare_node_closure "$res/vendor/node"
node_verify_list=$(mktemp "${TMPDIR:-/tmp}/gor-node-verify.XXXXXX")
if ! find "$res/vendor/node" -type f -print0 > "$node_verify_list"; then rm -f "$node_verify_list"; exit 1; fi
while IFS= read -r -d '' node_leaf; do
    node_kind=$(file -b "$node_leaf")
    case "$node_kind" in *Mach-O*) codesign --verify --strict "$node_leaf" ;; esac
 done < "$node_verify_list"
rm -f "$node_verify_list"
# Smoke tests dyld startup only, not wt_server imports/network/playback.
if ! "$res/vendor/node/node" -e "require('crypto');require('https');require('zlib')"; then
    echo 'node closure: staged node smoke check failed' >&2; exit 1
fi
# GOR_SIGNING_CONTINUITY_BEGIN
# Keep the installed app's signing identity across rebuilds. A certificate's
# display name alone (MacDev) is not identity: a replacement certificate may
# share that name. Check the new code against the installed designated
# requirement before any bundle rename. Never reset TCC or edit its database.
gor_read_designated_requirement() {
    local details requirement
    details=$(codesign --display --requirements - "$1" 2>&1) || return 1
    requirement=$(printf '%s\n' "$details" | sed -n 's/^designated => //p')
    [ -n "$requirement" ] || return 1
    printf '%s\n' "$requirement"
}
gor_verify_signing_continuity() {
    local candidate="$1" installed="$2" details old_requirement new_requirement
    codesign --verify --strict "$candidate" || return 1
    details=$(codesign --display --verbose=4 "$candidate" 2>&1) || return 1
    case "$details" in
        *Signature=adhoc*) echo 'Signing continuity: ad-hoc app refused; installed app unchanged.' >&2; return 1 ;;
    esac
    case "$details" in
        *Authority=*) ;;
        *) echo 'Signing continuity: certificate identity unavailable; installed app unchanged.' >&2; return 1 ;;
    esac
    new_requirement=$(gor_read_designated_requirement "$candidate") || return 1
    printf '      candidate designated requirement: %s\n' "$new_requirement"
    if [ -d "$installed" ]; then
        codesign --verify --strict "$installed" || {
            echo 'Signing continuity: installed signature cannot be verified; preserving it for inspection.' >&2
            return 1
        }
        old_requirement=$(gor_read_designated_requirement "$installed") || return 1
        printf '      installed designated requirement: %s\n' "$old_requirement"
        codesign --verify --strict --test-requirement "=$old_requirement" "$candidate" || {
            echo 'Signing continuity: new app does not satisfy installed identity; install refused.' >&2
            return 1
        }
        echo '      signing continuity: candidate satisfies installed designated requirement'
    else
        echo '      signing continuity: first install, certificate signature verified (no prior grant inferred)'
    fi
}
# GOR_SIGNING_CONTINUITY_END
gor_verify_signing_continuity "$staged_bundle" "$app_bundle" || exit 1
signed_executable_sha=$(shasum -a 256 "$dest/$app_name" | awk '{print $1}')
[ -n "$signed_executable_sha" ] || exit 1
echo "      signed executable sha256: $signed_executable_sha"
# Swap only after the new app passed build, resource, and signing checks.
# gor may have been reopened while compilation was running.
stop_running_gor
swap_started=$(date +%s)
backup_bundle="$project_root/$app_name.app.previous"
rm -rf "$backup_bundle"
if [ -d "$app_bundle" ]; then mv "$app_bundle" "$backup_bundle"; fi
if ! mv "$staged_bundle" "$app_bundle"; then
    if [ -d "$backup_bundle" ]; then mv "$backup_bundle" "$app_bundle"; fi
    exit 1
fi
installed_executable_sha=$(shasum -a 256 "$app_bundle/Contents/MacOS/$app_name" | awk '{print $1}')
if [ "$installed_executable_sha" != "$signed_executable_sha" ]; then
    echo 'Installed executable hash differs from verified candidate; refusing launch.' >&2
    exit 1
fi
echo "      installed executable sha256: $installed_executable_sha"
dev_vendor_committed=true
echo "      timing: swap $(( $(date +%s) - swap_started ))s"

# After the sealed app installs, commit the verified browser to source as one
# directory rename. Keep the old source for rollback. A failed build never
# mutates source. If promotion fails, keep stage so the next build can retry.
if [ "$chromium_stage_active" = true ]; then
    source_dir="$project_root/Resources/vendor/chromium/$staged_dir"
    source_backup="$build_dir/chromium-previous"
    if [ -e "$source_backup" ]; then
        echo "      chromium source promotion skipped: $source_backup exists; stage retained" >&2
    else
        if mv "$source_dir" "$source_backup"; then
            if mv "$chromium_stage/payload/$staged_dir" "$source_dir"; then
                rm -rf "$chromium_stage"
                echo "      chromium source promoted; old tree retained at $source_backup"
            else
                mv "$source_backup" "$source_dir"
                echo "      chromium source promotion failed; restored source, stage retained" >&2
            fi
        else
            echo "      chromium source promotion failed; stage retained" >&2
        fi
    fi
fi

if [ "$signing_enabled" = true ]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_bundle" 2>/dev/null || true
fi

# ── elapsed ───────────────────────────────────────────────────────────────────
end_time=$(date +%s)
elapsed=$((end_time - start_time))
next_step completion; echo "build complete. (${elapsed}s total)"
if [ "$open_app" = true ]; then
    # Lua reads this only on its first playback-restart after file-loaded.
    # Set it before launch, after the signed app has been installed.
    printf '%s\n' "$end_time" > "$playback_marker"
    echo "      build-complete epoch: $end_time (waiting for first mpv playback)"
fi

next_step dmg; echo "DMG..."
if [ "$create_dmg" = true ]; then
    hdiutil create -volname "Gor" -srcfolder "$app_bundle" -ov -format UDZO "$build_dir/$app_name.dmg" 2>/dev/null
    echo "      DMG ready: $build_dir/$app_name.dmg"
else
    echo "      skipped"
fi
finish_step
step_name=""

# ── launch + log ──────────────────────────────────────────────────────────────
if [ "$open_app" = true ]; then
    echo ""; echo "starting... [log: $log_mode]"
    # Escape the full executable path as an ERE, then anchor argv[0].
    # Do not let an unrelated gor.app elsewhere satisfy launch/exit checks.
    gor_process_pattern="^$(printf '%s' "$app_bundle/Contents/MacOS/$app_name" | sed 's/[][\.^$*+?(){}|]/\\&/g')([[:space:]]|$)"
    gor_is_running() {
        pgrep -u "$build_uid" -f "$gor_process_pattern" >/dev/null 2>&1
    }
    launch_open() {
        local open_started=$(date +%s)
        # Ask LaunchServices for a new instance of this exact bundle.
        open -n "$app_bundle"
        echo "      timing: macOS open returned in $(( $(date +%s) - open_started ))s"
        # open returns before Gatekeeper finishes. A process start timestamp
        # locates the extra delay, but is not proof that playback is ready.
        local deadline=$(( $(date +%s) + 120 ))
        while ! gor_is_running; do
            if [ "$(date +%s)" -ge "$deadline" ]; then
                echo "      timing: no gor process after $(( $(date +%s) - open_started ))s (verification/cancel may be pending)"
                return 1
            fi
            sleep 1
        done
        echo "      timing: macOS launch to gor process $(( $(date +%s) - open_started ))s (not playback-ready)"
    }

    wait_for_exit() {
        while gor_is_running; do sleep 1; done
    }

    if [ "$log_mode" = "direct" ]; then
        echo "      note: direct — /tmp/gor_direct.log (SCE enabled)"
        launch_open
        sleep 1
        # The shared EXIT cleanup stops only this build's viewer PID.
        # Bypass the tee for tail output; otherwise tail feeds its own log.
        tail -n 0 -F /tmp/gor_direct.log >&3 &
        TAILPID=$!
        wait_for_exit
        sleep 0.5
        stop_log_viewer
    fi

    if [ "$log_mode" = "off" ]; then
        launch_open
        wait_for_exit

    elif [ "$log_mode" = "filter" ]; then
        # [GOR]-prefixed NSLog only. Add NSLog(@"[GOR] ...") to code under test.
        # Produces AI-pasteable output — no noise, only your signal.
        launch_open
        sleep 1
        log stream --predicate 'process == "gor"' --level debug 2>/dev/null \
            | grep --line-buffered '\[GOR\]' &
        LOGPID=$!
        wait_for_exit
        kill $LOGPID 2>/dev/null

    elif [ "$log_mode" = "stream" ]; then
        # Standard NSLog output scoped to gor process.
        launch_open
        sleep 1
        log stream --predicate 'process == "gor"' --level debug 2>/dev/null &
        LOGPID=$!
        wait_for_exit
        kill $LOGPID 2>/dev/null

    elif [ "$log_mode" = "broad" ]; then
        # gor + mpv + Python (mus2). os_log from subprocesses.
        # raw print()/mpv stderr not capturable via open -a — TCC constraint.
        launch_open
        sleep 1
        log stream --predicate 'process == "gor" OR process == "mpv" OR process BEGINSWITH "Python"' \
            --level debug 2>/dev/null &
        LOGPID=$!
        wait_for_exit
        kill $LOGPID 2>/dev/null

    elif [ "$log_mode" = "full" ]; then
        # No predicate — entire system log. Last resort only.
        launch_open
        sleep 1
        log stream --level debug 2>/dev/null &
        LOGPID=$!
        wait_for_exit
        kill $LOGPID 2>/dev/null
    fi
fi


