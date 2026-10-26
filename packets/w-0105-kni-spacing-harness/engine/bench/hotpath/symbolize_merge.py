#!/usr/bin/env python3
"""symbolize_merge.py - SPEED-2 sample symbolizer + stage/crate folder (new bench file).

usage: symbolize_merge.py <binary> <samples.tsv> <stage_times.tsv> <run_idx> <out.tsv>

samples.tsv rows: ts, tid, state, raw_rip. <samples.tsv>.maps holds the process
maps captured at attach. Addresses are resolved per mapping: the main binary via
`nm -C --defined-only` (PIE slide from the maps file), other mappings by basename
(libc, vdso, anon, ...). Only running (state R) samples count as CPU time; parked
threads are folded into a per-stage "parked_or_idle" pseudo-row.

Emits TSV: stage, crate, function, samples, pct_of_stage, pct_of_run
"""
import subprocess, sys, bisect, collections, os

def load_symbols(binary):
    out = subprocess.run(["nm", "-C", "--defined-only", binary],
                         capture_output=True, text=True).stdout
    syms = []
    for line in out.splitlines():
        parts = line.split(" ", 2)
        if len(parts) == 3 and parts[1] in ("T", "t", "W", "w"):
            try:
                syms.append((int(parts[0], 16), parts[2]))
            except ValueError:
                pass
    syms.sort()
    return syms

def crate_of(sym):
    for c in ("kni_pipeline", "kni_core", "kni_metrics", "kni_learning", "rayon"):
        if sym.startswith(c + "::"):
            return c
    if sym.startswith(("std::", "core::", "alloc::")):
        return "std"
    return "other"

def load_maps(path):
    maps = []
    for line in open(path):
        parts = line.split()
        if len(parts) < 6:
            continue
        lo, hi = (int(x, 16) for x in parts[0].split("-"))
        maps.append((lo, hi, os.path.basename(parts[5])))
    maps.sort()
    return maps

def main():
    binary, samples_tsv, stage_tsv, run_idx, out_tsv = sys.argv[1:6]
    syms = load_symbols(binary)
    addrs = [a for a, _ in syms]
    maps = load_maps(samples_tsv + ".maps")
    exe = os.path.basename(binary)
    exe_base = next((lo for lo, hi, name in maps if name == exe), 0)

    windows = []
    with open(stage_tsv) as f:
        next(f)
        for line in f:
            r, stage, t0, t1, _ = line.rstrip("\n").split("\t")
            if r == run_idx:
                windows.append((float(t0), float(t1), stage))

    def stage_of(ts):
        for t0, t1, s in windows:
            if t0 <= ts < t1:
                return s
        return "outside_stages"

    def resolve(rip):
        for lo, hi, name in maps:
            if lo <= rip < hi:
                if name == exe:
                    off = rip - exe_base
                    i = bisect.bisect_right(addrs, off) - 1
                    return (crate_of(syms[i][1]) if i >= 0 else "other",
                            syms[i][1] if i >= 0 else f"unknown_{off:#x}")
                return ("native" if name else "anon", name or "[anon]")
        return ("other", f"unmapped_{rip:#x}")

    counts = collections.Counter()
    stage_tot = collections.Counter()
    total = 0
    parked = collections.Counter()
    with open(samples_tsv) as f:
        for line in f:
            if line.startswith("#"):
                continue
            cells = line.rstrip("\n").split("\t")
            ts, state, rip = float(cells[0]), cells[2], int(cells[3], 16)
            stage = stage_of(ts)
            if state != "R":
                parked[stage] += 1
                continue
            crate, sym = resolve(rip)
            counts[(stage, crate, sym)] += 1
            stage_tot[stage] += 1
            total += 1

    with open(out_tsv, "w") as f:
        f.write("stage\tcrate\tfunction\tsamples\tpct_of_stage\tpct_of_run\n")
        for (stage, crate, sym), n in sorted(counts.items(), key=lambda kv: -kv[1]):
            f.write(f"{stage}\t{crate}\t{sym}\t{n}\t{100.0*n/max(stage_tot[stage],1):.2f}\t{100.0*n/max(total,1):.2f}\n")
        for stage, n in sorted(parked.items()):
            f.write(f"{stage}\tparked_or_idle\t[thread parked/idle at sample]\t{n}\t-\t-\n")
    print(f"{total} running samples -> {out_tsv} ({sum(parked.values())} parked samples folded)")

if __name__ == "__main__":
    main()
