#!/usr/bin/env python3
"""W-0085 requester-supplied fixture: CPU competitor process.
Busy-spins while the flag file exists; when the flag is absent it idles,
re-checking roughly every 5 ms. Runs until --max-s seconds elapse (or the
parent process terminates it); it does NOT exit when the flag disappears.
Usage: python3 w0085_competitor.py FLAGFILE [--max-s 600]
"""
import os, sys, time

def main():
    flag = sys.argv[1]
    maxs = float(sys.argv[3]) if len(sys.argv) > 3 else 600.0
    t0 = time.monotonic()
    x = 0
    while time.monotonic() - t0 < maxs:
        if not os.path.exists(flag):
            time.sleep(0.005)
            continue
        t1 = time.monotonic() + 0.005
        while time.monotonic() < t1:
            x += 1  # busy spin (syscall-free; flag re-checked at 5ms cadence)
    print("competitor exit", x)

if __name__ == "__main__":
    main()
