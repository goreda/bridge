#!/usr/bin/env python3
"""run_timed.py - SPEED-2 stage wall-clock harness (new bench file, additive).

Runs the kni-pipeline binary on a manifest REPEATS times, timestamps the binary's
own stderr progress markers, and writes per-stage wall-clock rows.

usage: run_timed.py <binary> <manifest> <outdir> <repeats> <results.tsv> \
         [--sampler <rip_sampler> <hz> <samples.tsv>] [-- <extra flags...>]

With --sampler, the LAST run is sampled: rip_sampler is spawned against the
pipeline pid right after launch.

Output TSV columns: run_idx, stage, t_start_s, t_end_s, wall_s (monotonic clock,
seconds since process spawn of that run).
"""
import subprocess, sys, time, os, shutil

# DECLARED_CONVENTION: markers emitted by pipeline/src/main.rs (see README.md).
MARKERS = [
    ("stage2_profiles", "progress stage2 profiles"),
    ("stage3_spacing", "progress stage3 spacing"),
    ("stage4_residual_kern", "progress stage4 residual kern"),
    ("stage5_assembly", "progress stage5 assembly"),
    ("stage6_export", "progress stage6 export"),
]

def one_run(run_idx, binary, manifest, outdir, flags, tsv, keep=False, sampler=None):
    if os.path.isdir(outdir):
        shutil.rmtree(outdir)
    t0 = time.monotonic()
    p = subprocess.Popen([binary, manifest, outdir] + flags,
                         stdout=subprocess.DEVNULL,
                         stderr=subprocess.PIPE, text=True, bufsize=1)
    sampler_proc = None
    if sampler is not None:
        sampler_proc = subprocess.Popen([sampler[0], str(p.pid), sampler[1], sampler[2]])
    marks = []  # (t, stage_name)
    for line in p.stderr:
        t = time.monotonic() - t0
        for stage, marker in MARKERS:
            if line.strip() == marker:
                marks.append((t, stage))
        sys.stderr.write(f"\r  run {run_idx}: {t:8.1f}s {line.strip()[:70]:<70}")
        sys.stderr.flush()
    rc = p.wait()
    t_end = time.monotonic() - t0
    if sampler_proc is not None:
        sampler_proc.wait()
    sys.stderr.write(f"\r  run {run_idx}: exit {rc} after {t_end:.1f}s{'':40}\n")
    rows = []
    prev_t, prev_name = 0.0, "stage1_capture_fit"
    for t, stage in marks:
        rows.append((run_idx, prev_name, prev_t, t, t - prev_t))
        prev_t, prev_name = t, stage
    rows.append((run_idx, prev_name, prev_t, t_end, t_end - prev_t))
    with open(tsv, "a") as f:
        for r in rows:
            f.write("\t".join([str(r[0]), r[1], f"{r[2]:.3f}", f"{r[3]:.3f}", f"{r[4]:.3f}"]) + "\n")
    if not keep and os.path.isdir(outdir):
        shutil.rmtree(outdir)
    return rc

def main():
    binary, manifest, outdir, repeats, tsv = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5]
    rest = sys.argv[6:]
    sampler = None
    if rest[:1] == ["--sampler"]:
        sampler = rest[1:4]
        rest = rest[4:]
    flags = rest[1:] if rest[:1] == ["--"] else []
    if not os.path.exists(tsv):
        with open(tsv, "w") as f:
            f.write("run_idx\tstage\tt_start_s\tt_end_s\twall_s\n")
    for i in range(repeats):
        last = i == repeats - 1
        rc = one_run(i + 1, binary, manifest, outdir, flags, tsv, keep=last,
                     sampler=sampler if last else None)
        if rc != 0:
            print(f"run {i + 1} exited {rc}; aborting repeats", file=sys.stderr)
            sys.exit(rc)
    import statistics
    stages = {}
    with open(tsv) as f:
        next(f)
        for line in f:
            _, stage, _, _, wall = line.rstrip("\n").split("\t")
            stages.setdefault(stage, []).append(float(wall))
    print(f"{'stage':<24} {'mean_s':>9} {'min_s':>9} {'max_s':>9} {'n':>3}")
    for stage, vals in stages.items():
        print(f"{stage:<24} {statistics.mean(vals):9.3f} {min(vals):9.3f} {max(vals):9.3f} {len(vals):3d}")

if __name__ == "__main__":
    main()
