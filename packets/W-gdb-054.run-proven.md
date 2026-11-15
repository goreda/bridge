# W-gdb-054 return-to-lab: W-0286/B7 transport kit test_wire startup-race flake (1nstinct) [rev 2]
state: candidate
solver lab: 1nstinct
reviewer lab: gdb integrator (gorav lane)
id: W-gdb-054

```packet-json
{
  "packet_id": "W-gdb-054",
  "writer": "gdb",
  "code_owner": "1nstinct (owning lab, transport allocation)",
  "product_repo": "goreda/gorav",
  "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
  "scope": "product",
  "touched_files": [
    {
      "path": "kits/b7-transport-flake/tests/run_e2e.sh",
      "excerpt_block": "source1"
    },
    {
      "path": "kits/b7-transport-flake/tests/test_wire.c",
      "excerpt_block": "source2"
    },
    {
      "path": "kits/b7-transport-flake/gen_mutants.py",
      "excerpt_block": "source3"
    }
  ],
  "interface": {
    "signatures": "run_e2e.sh orchestration (source1): python3 synth_server.py $PORT & sleep 1; then e2e_client scenarios + test_wire $PORT; test_wire W1-W6 assertions (source2: W2/W3/W4, the failing sites)",
    "types": "test_wire CHECK(cond) prints FAIL file:line; WIRE RESULT: FAIL (n); e2e E2E RESULT: PASS|FAIL",
    "ownership_lifetime": "synth server process owned by the script (kill at exit); carrier files verbatim from the G0746 archive with CARRIER.sha256",
    "caller": "gorav lane ingest gate (kits/b7-transport-flake/check.py)",
    "callee": "1nstinct w0286 kit (rt_transport + rt_wire_posix + synth_server.py)"
  },
  "test": {
    "command": "cd kits/b7-transport-flake && python3 check.py",
    "expected": "exit 0; stdout 'b7-transport-flake: 4/4 checks PASS' (carrier integrity, build, mutant-A-no-server exactly the 6 observed FAIL sites, mutant-B-fixed-e2e WIRE+E2E PASS)",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "kits/b7-transport-flake/"
    ],
    "return_form": "patch"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "kits/b7-transport-flake/CARRIER.sha256",
        "block": "kit1"
      },
      {
        "path": "kits/b7-transport-flake/Makefile",
        "block": "kit2"
      },
      {
        "path": "kits/b7-transport-flake/check.py",
        "block": "kit3"
      },
      {
        "path": "kits/b7-transport-flake/gen_mutants.py",
        "block": "kit4"
      },
      {
        "path": "kits/b7-transport-flake/src/rt_avformat_adapter.h",
        "block": "kit5"
      },
      {
        "path": "kits/b7-transport-flake/src/rt_transport.c",
        "block": "kit6"
      },
      {
        "path": "kits/b7-transport-flake/src/rt_transport.h",
        "block": "kit7"
      },
      {
        "path": "kits/b7-transport-flake/src/rt_wire_posix.c",
        "block": "kit8"
      },
      {
        "path": "kits/b7-transport-flake/src/rt_wire_posix.h",
        "block": "kit9"
      },
      {
        "path": "kits/b7-transport-flake/tests/e2e_client.c",
        "block": "kit10"
      },
      {
        "path": "kits/b7-transport-flake/tests/run_e2e.sh",
        "block": "kit11"
      },
      {
        "path": "kits/b7-transport-flake/tests/run_e2e_fix.sh",
        "block": "kit12"
      },
      {
        "path": "kits/b7-transport-flake/tests/synth_server.py",
        "block": "kit13"
      },
      {
        "path": "kits/b7-transport-flake/tests/test_wire.c",
        "block": "kit14"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
    "command": "cd kits/b7-transport-flake && python3 check.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:13:10.757125+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "b7-transport-flake: 4/4 checks PASS",
    "inline_files": [
      {
        "path": "kits/b7-transport-flake/CARRIER.sha256",
        "block": "kit1",
        "sha256": "6b3dc58f4791b3c72c31fdfbd67ce7f91e0b940054dc3d0b4518347079eb19e0"
      },
      {
        "path": "kits/b7-transport-flake/Makefile",
        "block": "kit2",
        "sha256": "c3ba8326f754c6a9f550641b39adbb231d19ba8d20c5ea46d7a3b03cbb3ff305"
      },
      {
        "path": "kits/b7-transport-flake/check.py",
        "block": "kit3",
        "sha256": "6b16ff30e1d9165b859d698535f59053c50fd2ba5629e29c6d5fbdcf2bfbac77"
      },
      {
        "path": "kits/b7-transport-flake/gen_mutants.py",
        "block": "kit4",
        "sha256": "a72cdaa2877b824ede72299fdc53aad823d8868c54b83bd15365b62ce56b1940"
      },
      {
        "path": "kits/b7-transport-flake/src/rt_avformat_adapter.h",
        "block": "kit5",
        "sha256": "fd488446854d939b67665f4d2996ab8be3ebfc3306058e43a7cae963ca519dac"
      },
      {
        "path": "kits/b7-transport-flake/src/rt_transport.c",
        "block": "kit6",
        "sha256": "ea4692c2f63bc7571c2f7abb72bfc59ff0d27594b9af0068f0558ac9d21aecb5"
      },
      {
        "path": "kits/b7-transport-flake/src/rt_transport.h",
        "block": "kit7",
        "sha256": "ed33bee406971ef98c3aa6f85df2258779e366e7844070426e3322a8782005f5"
      },
      {
        "path": "kits/b7-transport-flake/src/rt_wire_posix.c",
        "block": "kit8",
        "sha256": "c7b370d7bc2456c48cc5fbeb9e40f306770c00371e2a61a6181b61b7ae8a58e1"
      },
      {
        "path": "kits/b7-transport-flake/src/rt_wire_posix.h",
        "block": "kit9",
        "sha256": "4c3dab7f21d66abe1b0de46abc0bb50d4d31752cd9df14b8f0ebe280db002a0b"
      },
      {
        "path": "kits/b7-transport-flake/tests/e2e_client.c",
        "block": "kit10",
        "sha256": "154bd0da32bec852363c41dc359e98637fe843571ce12ec2fc72a657415ecadc"
      },
      {
        "path": "kits/b7-transport-flake/tests/run_e2e.sh",
        "block": "kit11",
        "sha256": "3b43b5a1dddf9722cd0b1ca92f1113aaf4f9a65bd8b0b9fa0355d3619f16152d"
      },
      {
        "path": "kits/b7-transport-flake/tests/run_e2e_fix.sh",
        "block": "kit12",
        "sha256": "a76e4044a9089a13759cdddb586e04322b6b75dcb4ad3b552f21a35a161d01eb"
      },
      {
        "path": "kits/b7-transport-flake/tests/synth_server.py",
        "block": "kit13",
        "sha256": "b174dff104e976b39a9f22d9e124dedb44395c07d002f7cc24af8537bd72c37c"
      },
      {
        "path": "kits/b7-transport-flake/tests/test_wire.c",
        "block": "kit14",
        "sha256": "c90a4d81cc8987d95437ac85a142d69fd5fe6fa7cf959c2cdf63025857d0d3a6"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "59c2faa3fb95e37b32f341f714a2e4876746f74230ae9639b6bd866249cc1ec3",
    "last_5_lines": [
      "PASS carrier-integrity",
      "PASS build",
      "PASS mutant-A-no-server (exactly the 6 observed sites)",
      "PASS mutant-B-fixed-e2e",
      "b7-transport-flake: 4/4 checks PASS"
    ],
    "receipt_sha256": "bb4986722518da5ef2403a6463c92110d815944dc9f41e875694d08392a742fa"
  }
}
```

## problem (what fails)
W-0286/B7 rev2 kit e2e has a startup-race flake observed by the integrator at ingest: first `sh tests/run_e2e.sh` gave WIRE RESULT: FAIL (6), immediate retry passed. This packet returns the kit WITH the failing test executable, not a prose description.

## observed cause vs hypothesis (separated, per gate ruling)
- OBSERVED (reproduced here, mutant A): with nothing listening on the port, tests/test_wire fails at exactly six sites - tests/test_wire.c:49, 61, 66 (W2/W3 server fetches), 75, 77, 82 (W4) - and prints WIRE RESULT: FAIL (6). W1 and both connect-bounds checks pass without a server. The six-site signature of the original flake and of the no-server run are identical.
- HYPOTHESIS (plausible, not proven): the original first-run flake came from the fixed `sleep 1` startup window in run_e2e.sh (source1) expiring before synth_server.py was listening. No port-reuse evidence exists; no second mechanism is claimed.

## carrier pin (verbatim from the G0746 archive, 1nstinct)
kits/b7-transport-flake/ carries src/ + tests/ + Makefile byte-verbatim (CARRIER.sha256 in the kit; run_e2e.sh sha256 3b43b5a1dddf9722cd0b1ca92f1113aaf4f9a65bd8b0b9fa0355d3619f16152d, test_wire.c c90a4d81cc8987d95437ac85a142d69fd5fe6fa7cf959c2cdf63025857d0d3a6, synth_server.py b174dff104e976b39a9f22d9e124dedb44395c07d002f7cc24af8537bd72c37c).

## fix contract for the owning lab
replace the fixed `sleep 1` with a bounded readiness poll on the port (mutant B in gen_mutants.py shows one: 100ms interval, 5.0s deadline, named readiness-timeout error). The kit closes when the upstream run_e2e.sh itself carries the bounded poll and two consecutive runs PASS under host load.

## acceptance test (executable, bounded)
cd kits/b7-transport-flake && python3 check.py exits 0: builds the carrier (gcc), runs mutant A (bounded 60s) expecting exactly the six FAIL sites, generates and runs mutant B (bounded 180s) expecting WIRE+E2E PASS.

## pinned excerpts
### kits/b7-transport-flake/tests/run_e2e.sh (carrier, full file; the fixed `sleep 1` window is the flake locus)
```sh id=source1
#!/bin/sh
# W-0286 e2e: synthetic server + posix-wire client. No real endpoints.
set -u
cd "$(dirname "$0")"
if [ "${RT_SAN:-0}" = 1 ]; then alias_true=1; fi
CLI=./e2e_client; WIRE=./test_wire
if [ "${RT_SAN:-0}" = 1 ]; then CLI=./e2e_client_san; WIRE=./test_wire_san; fi
PORT=8971
python3 synth_server.py $PORT & SRV=$!
sleep 1
F=0
run() { echo "== $*"; "$@" || F=1; }
run $CLI http://127.0.0.1:$PORT/full    full   1048576
run $CLI http://127.0.0.1:$PORT/drop    full   300000
run $CLI http://127.0.0.1:$PORT/dribble full   200000
run $CLI http://127.0.0.1:$PORT/norange full   150000
run $CLI http://127.0.0.1:$PORT/chunked full   120000
run $CLI http://127.0.0.1:$PORT/full    seek   1048576
run $CLI http://127.0.0.1:$PORT/dribble cancel 100000
run $WIRE $PORT
kill $SRV 2>/dev/null
[ $F -eq 0 ] && echo "E2E RESULT: PASS" || echo "E2E RESULT: FAIL"
exit $F
```
### kits/b7-transport-flake/tests/test_wire.c (carrier, lines 41-90: W2/W3/W4 - the six failing assertion sites)
```c id=source2
    {
        RTWire w; rt_wire_posix_open(&w, 2000);
        char url[4200];
        snprintf(url, sizeof url, "http://127.0.0.1:%d/", port);
        size_t base = strlen(url);
        memset(url + base, 'a', 4000); url[base + 4000] = 0;
        RTTransport *t = NULL;
        int rc = rt_open(&t, &w, url, NULL);
        CHECK(rc == RT_ERR_PROTOCOL && t == NULL);
        rt_wire_posix_free(&w);
    }
    /* W3: 3000-char extra header fits -> normal fetch works byte-exact */
    {
        RTWire w; rt_wire_posix_open(&w, 2000);
        static char big[3001]; memset(big, 'H', 2990); big[2990] = 0;
        memcpy(big, "X-Pad: ", 7);
        const char *hdrs[1] = { big };
        RTOptions o = {0}; o.extra_headers = hdrs; o.n_extra_headers = 1;
        char url[64]; snprintf(url, sizeof url, "http://127.0.0.1:%d/norange", port);
        RTTransport *t = NULL;
        CHECK(rt_open(&t, &w, url, &o) == RT_OK);
        uint8_t b[8192]; size_t got = 0; ptrdiff_t n; int okd = 1;
        while ((n = rt_read(t, b, sizeof b)) > 0)
            for (ptrdiff_t i = 0; i < n; i++)
                if (b[i] != (uint8_t)((got++) * 131u + 17u)) okd = 0;
        CHECK(n == 0 && okd && got == 150000);
        rt_close(t);
        rt_wire_posix_free(&w);
    }
    /* W4: bare-LF response lines parse correctly (read_line CR strip fix) */
    {
        RTWire w; rt_wire_posix_open(&w, 2000);
        char url[64]; snprintf(url, sizeof url, "http://127.0.0.1:%d/barelf", port);
        RTTransport *t = NULL;
        CHECK(rt_open(&t, &w, url, NULL) == RT_OK);
        RTCapabilities c; rt_get_capabilities(t, &c);
        CHECK(c.size_known && c.size == 50000);
        uint8_t b[8192]; size_t got = 0; ptrdiff_t n; int okd = 1;
        while ((n = rt_read(t, b, sizeof b)) > 0)
            for (ptrdiff_t i = 0; i < n; i++)
                if (b[i] != (uint8_t)((got++) * 131u + 17u)) okd = 0;
        CHECK(n == 0 && okd && got == 50000);
        rt_close(t);
        rt_wire_posix_free(&w);
    }
    /* W5: connect timeout bounds an unreachable host */
    {
        RTWire w; RTWirePosixConfig cfg = { 500, 300, NULL, NULL };
        rt_wire_posix_open_cfg(&w, &cfg);
        RTTransport *t = NULL;
```
### kits/b7-transport-flake/gen_mutants.py (executable mutant generator, full file)
```python id=source3
#!/usr/bin/env python3
"""gen_mutants.py - W-gdb-054: produce the two executable mutants.

Mutant A (no-server): nothing to generate - check.py runs tests/test_wire
with no synthetic server listening (observed cause of the 6 FAILs).

Mutant B (fix): tests/run_e2e_fix.sh - the carrier run_e2e.sh with the fixed
`sleep 1` startup window replaced by a bounded readiness poll (deadline 5s,
hard fail with a named error), on a distinct port to avoid collisions.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent
src = (ROOT / "tests" / "run_e2e.sh").read_text()

POLL = (
    "python3 - \"$PORT\" <<'PYEOF'\n"
    "import socket, sys, time\n"
    "port = int(sys.argv[1]); deadline = time.monotonic() + 5.0\n"
    "while True:\n"
    "    s = socket.socket()\n"
    "    try:\n"
    "        s.connect((\"127.0.0.1\", port)); s.close(); break\n"
    "    except OSError:\n"
    "        s.close()\n"
    "        if time.monotonic() > deadline:\n"
    "            print(\"readiness-timeout: synth server not listening after 5.0s\", file=sys.stderr)\n"
    "            sys.exit(2)\n"
    "        time.sleep(0.1)\n"
    "PYEOF\n"
)

if "sleep 1\n" not in src:
    print("carrier run_e2e.sh does not contain the expected `sleep 1` line", file=sys.stderr)
    sys.exit(2)

mutant = src.replace("PORT=8971", "PORT=8973")
mutant = mutant.replace("sleep 1\n", POLL)
out = ROOT / "tests" / "run_e2e_fix.sh"
out.write_text(mutant)
out.chmod(0o755)
print("wrote tests/run_e2e_fix.sh (port 8973, bounded readiness poll 5.0s)")
```


## roles and state
solver lab: 1nstinct. reviewer lab: gdb integrator. Returned with the failing test per arch-196q item 3; the kit stays out of the merge set until the flake closes upstream.

secret scan: clean

```json id=fixtures1
[{"check": "mutant A no-server", "expect": "exactly FAIL tests/test_wire.c:49,61,66,75,77,82 + WIRE RESULT: FAIL (6)"}, {"check": "mutant B fixed e2e", "expect": "WIRE RESULT: PASS + E2E RESULT: PASS, rc 0"}, {"check": "carrier integrity", "expect": "all CARRIER.sha256 entries match"}]
```

```text id=kit1
fd488446854d939b67665f4d2996ab8be3ebfc3306058e43a7cae963ca519dac  src/rt_avformat_adapter.h
ea4692c2f63bc7571c2f7abb72bfc59ff0d27594b9af0068f0558ac9d21aecb5  src/rt_transport.c
ed33bee406971ef98c3aa6f85df2258779e366e7844070426e3322a8782005f5  src/rt_transport.h
c7b370d7bc2456c48cc5fbeb9e40f306770c00371e2a61a6181b61b7ae8a58e1  src/rt_wire_posix.c
4c3dab7f21d66abe1b0de46abc0bb50d4d31752cd9df14b8f0ebe280db002a0b  src/rt_wire_posix.h
154bd0da32bec852363c41dc359e98637fe843571ce12ec2fc72a657415ecadc  tests/e2e_client.c
3b43b5a1dddf9722cd0b1ca92f1113aaf4f9a65bd8b0b9fa0355d3619f16152d  tests/run_e2e.sh
b174dff104e976b39a9f22d9e124dedb44395c07d002f7cc24af8537bd72c37c  tests/synth_server.py
c90a4d81cc8987d95437ac85a142d69fd5fe6fa7cf959c2cdf63025857d0d3a6  tests/test_wire.c
c3ba8326f754c6a9f550641b39adbb231d19ba8d20c5ea46d7a3b03cbb3ff305  Makefile

```

```text id=kit2
CC ?= gcc
CFLAGS ?= -std=gnu11 -O2 -Wall -Wextra -Werror -I src
SRC = src/rt_transport.c src/rt_wire_posix.c

all: tests/test_engine tests/e2e_client tests/test_wire

tests/test_engine: tests/test_engine.c src/rt_transport.c src/rt_transport.h
	$(CC) $(CFLAGS) -o $@ tests/test_engine.c src/rt_transport.c

tests/e2e_client: tests/e2e_client.c $(SRC) src/rt_transport.h src/rt_wire_posix.h
	$(CC) $(CFLAGS) -o $@ tests/e2e_client.c $(SRC)

tests/test_wire: tests/test_wire.c $(SRC) src/rt_transport.h src/rt_wire_posix.h
	$(CC) $(CFLAGS) -o $@ tests/test_wire.c $(SRC)

check: all
	./tests/test_engine
	sh tests/run_e2e.sh

check-san:
	$(CC) $(CFLAGS) -fsanitize=address,undefined -g -o tests/test_engine_san tests/test_engine.c src/rt_transport.c
	$(CC) $(CFLAGS) -fsanitize=address,undefined -g -o tests/e2e_client_san tests/e2e_client.c $(SRC)
	$(CC) $(CFLAGS) -fsanitize=address,undefined -g -o tests/test_wire_san tests/test_wire.c $(SRC)
	./tests/test_engine_san
	RT_SAN=1 sh tests/run_e2e.sh

clean:
	rm -f tests/test_engine tests/e2e_client tests/test_wire tests/*_san
.PHONY: all check check-san clean

```

```python id=kit3
#!/usr/bin/env python3
"""check.py - W-gdb-054 bounded executable gate.

Runs, in order, everything bounded:
 1. carrier integrity: CARRIER.sha256 must match the files on disk
 2. build: make e2e_client + test_wire (gcc, bounded)
 3. mutant A (no-server): tests/test_wire on a port with no listener must
    produce exactly the six observed FAIL sites and WIRE RESULT: FAIL (6)
 4. mutant B (fix): gen_mutants.py output run_e2e_fix.sh must print
    WIRE RESULT: PASS and E2E RESULT: PASS

Prints one line per check; exits 0 only when all four pass.
"""
import hashlib
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent
EXPECTED_FAIL_SITES = [
    "tests/test_wire.c:49", "tests/test_wire.c:61", "tests/test_wire.c:66",
    "tests/test_wire.c:75", "tests/test_wire.c:77", "tests/test_wire.c:82",
]


def run(cmd, timeout, **kw):
    return subprocess.run(cmd, cwd=ROOT, timeout=timeout,
                          capture_output=True, text=True, **kw)


def check_carrier():
    ok = True
    for line in (ROOT / "CARRIER.sha256").read_text().splitlines():
        want, rel = line.split(None, 1)
        got = hashlib.sha256((ROOT / rel).read_bytes()).hexdigest()
        if got != want:
            print(f"FAIL carrier mismatch: {rel}")
            ok = False
    if ok:
        print("PASS carrier-integrity")
    return ok


def check_build():
    r = run(["make", "tests/e2e_client", "tests/test_wire"], timeout=180)
    if r.returncode != 0:
        print("FAIL build:", r.stdout[-400:], r.stderr[-400:])
        return False
    print("PASS build")
    return True


def check_mutant_no_server():
    # Mutant A: no synthetic server anywhere on 8971; test_wire must FAIL at
    # exactly the six observed sites. This is the observed cause: every
    # server-dependent assertion fails when nothing listens.
    r = run(["./tests/test_wire", "8971"], timeout=60)
    out = r.stdout
    sites = re.findall(r"FAIL (tests/test_wire\.c:\d+)", out)
    if sites == EXPECTED_FAIL_SITES and "WIRE RESULT: FAIL (6)" in out:
        print("PASS mutant-A-no-server (exactly the 6 observed sites)")
        return True
    print(f"FAIL mutant-A-no-server: sites={sites} tail={out[-200:]!r}")
    return False


def check_mutant_fix():
    g = run([sys.executable, "gen_mutants.py"], timeout=30)
    if g.returncode != 0:
        print("FAIL gen_mutants:", g.stdout, g.stderr)
        return False
    r = run(["sh", "tests/run_e2e_fix.sh"], timeout=180)
    out = r.stdout
    if "WIRE RESULT: PASS" in out and "E2E RESULT: PASS" in out and r.returncode == 0:
        print("PASS mutant-B-fixed-e2e")
        return True
    print(f"FAIL mutant-B-fixed-e2e rc={r.returncode} tail={out[-300:]!r} err={r.stderr[-200:]!r}")
    return False


def main():
    results = [check_carrier(), check_build(), check_mutant_no_server(), check_mutant_fix()]
    passed = sum(results)
    print(f"b7-transport-flake: {passed}/4 checks PASS")
    return 0 if passed == 4 else 1


if __name__ == "__main__":
    sys.exit(main())

```

```python id=kit4
#!/usr/bin/env python3
"""gen_mutants.py - W-gdb-054: produce the two executable mutants.

Mutant A (no-server): nothing to generate - check.py runs tests/test_wire
with no synthetic server listening (observed cause of the 6 FAILs).

Mutant B (fix): tests/run_e2e_fix.sh - the carrier run_e2e.sh with the fixed
`sleep 1` startup window replaced by a bounded readiness poll (deadline 5s,
hard fail with a named error), on a distinct port to avoid collisions.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent
src = (ROOT / "tests" / "run_e2e.sh").read_text()

POLL = (
    "python3 - \"$PORT\" <<'PYEOF'\n"
    "import socket, sys, time\n"
    "port = int(sys.argv[1]); deadline = time.monotonic() + 5.0\n"
    "while True:\n"
    "    s = socket.socket()\n"
    "    try:\n"
    "        s.connect((\"127.0.0.1\", port)); s.close(); break\n"
    "    except OSError:\n"
    "        s.close()\n"
    "        if time.monotonic() > deadline:\n"
    "            print(\"readiness-timeout: synth server not listening after 5.0s\", file=sys.stderr)\n"
    "            sys.exit(2)\n"
    "        time.sleep(0.1)\n"
    "PYEOF\n"
)

if "sleep 1\n" not in src:
    print("carrier run_e2e.sh does not contain the expected `sleep 1` line", file=sys.stderr)
    sys.exit(2)

mutant = src.replace("PORT=8971", "PORT=8973")
mutant = mutant.replace("sleep 1\n", POLL)
out = ROOT / "tests" / "run_e2e_fix.sh"
out.write_text(mutant)
out.chmod(0o755)
print("wrote tests/run_e2e_fix.sh (port 8973, bounded readiness poll 5.0s)")

```

```text id=kit5
/* rt_avformat_adapter.h - PROPOSED avformat binding for rt_transport.
 *
 * STATUS: PROPOSED / BLOCKED_INPUT. This workspace has no FFmpeg dev
 * headers, so this binding cannot be compiled or verified here. It is a
 * pinned mapping of rt_transport onto avformat's URLProtocol contract,
 * recorded so the local integrator can wire it in the native build lane
 * without re-deriving semantics. Version pins that MUST be confirmed
 * against the integrator's avformat before acceptance:
 *   - URLProtocol struct layout (ffurl_* era vs avio_* era fields)
 *   - AVSEEK_SIZE / AVSEEK_FORCE whence bits (we mirror 0x10000)
 *   - AVIOInterruptCB semantics (nonzero return = abort)
 *   - AVERROR mapping of RTStatus codes
 * Nothing below invents server behavior; it only maps engine semantics.
 */
#ifndef RT_AVFORMAT_ADAPTER_H
#define RT_AVFORMAT_ADAPTER_H

#include "rt_transport.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Pinned mapping (proposed):
 *
 *   URLProtocol.url_open   -> rt_wire_posix_open (or integrator wire) +
 *                             rt_open; probe runs here, capabilities fixed
 *                             for the session.
 *   URLProtocol.url_read   -> rt_read; 0 at clean EOF, AVERROR(...) for
 *                             negative RTStatus (mapping table below).
 *   URLProtocol.url_seek   -> rt_seek64; supports SEEK_SET/CUR/END and
 *                             AVSEEK_SIZE (== RT_SEEK_SIZE). Seek on a
 *                             non-seekable resource returns
 *                             AVERROR(ENOSYS) from RT_ERR_NOT_SEEKABLE.
 *   URLProtocol.url_close  -> rt_close.
 *   URLProtocol.url_get_short_seek -> 0 (no short-seek fast path claimed;
 *                             every seek revalidates the entity).
 *   URLProtocol.url_get_file_handle -> -1 (no fd exposed; wire-owned).
 *   AVIOContext.interrupt_callback -> RTOptions.interrupt, checked before
 *                             every wire request, recv and retry sleep.
 *
 * Proposed AVERROR mapping (integrator confirms exact values per its
 * avutil version):
 *   RT_ERR_NETWORK/RT_ERR_RETRY_EXHAUSTED -> AVERROR(EIO)
 *   RT_ERR_PROTOCOL/RANGE_REFUSED         -> AVERROR_INVALIDDATA? NO -
 *       PROPOSED: AVERROR(ENOSYS) is wrong here; use AVERROR_PROTOCOL_
 *       FAILURE where present, else AVERROR(EIO) with log. PIN REQUIRED.
 *   RT_ERR_NOT_SEEKABLE                   -> AVERROR(ENOSYS) on seek,
 *                                            AVERROR(EPIPE)? NO. PIN.
 *   RT_ERR_ENTITY_CHANGED                 -> AVERROR_INVALIDDATA
 *   RT_ERR_CANCELLED                      -> AVERROR_EXIT
 *
 * Capability signaling (proposed): rt_get_capabilities snapshot is
 * exposed to the host as avpriv/options, NOT silently:
 *   - range_supported=false  -> AVIOContext.seekable = 0
 *   - range_supported=true   -> AVIOContext.seekable = AVIO_SEEKABLE_NORMAL
 *   - size_known             -> avio_size() answerable via RT_SEEK_SIZE
 *   - etag/last_modified     -> surfaced for cache validation by host
 * Backpressure contract (proposed): URLProtocol has no pull-based flow
 * control; the engine honors max_read_chunk as its recv window so a slow
 * relay never forces unbounded buffering. Integrator sets the window
 * from its cache policy at open time.
 */

/* Glue the integrator implements (sketch, compiles only with real avformat):
 *
 *   static int rt_avio_open(URLContext *h, const char *url, int flags) {
 *       RTOptions o = {0};
 *       o.interrupt = (RTInterruptFn)ff_check_interrupt;   // wraps avio cb
 *       o.interrupt_opaque = &h->interrupt_callback;
 *       o.max_read_chunk = RT_AVIO_WINDOW;                 // host policy
 *       RTWire wire; rt_wire_posix_open(&wire, 5000);      // or host wire
 *       return map_err(rt_open(&((RTPriv*)h->priv_data)->t, &wire, url, &o));
 *   }
 */

#ifdef __cplusplus
}
#endif
#endif

```

```text id=kit6
/* rt_transport.c - engine for W-0286 / 195b-B7. See rt_transport.h. */
#include "rt_transport.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>
#include <errno.h>
#include <limits.h>
#include <strings.h> /* strncasecmp */

struct RTTransport {
    RTWire wire;
    char *url;
    RTOptions opts;
    /* capabilities */
    bool range_supported, size_known;
    uint64_t size;
    bool etag_known;      char etag[160];
    bool lm_known;        char last_modified[96];
    char server[128];
    /* stream state */
    bool exchange_open;   /* a body-bearing exchange is open at pos */
    bool body_known;      /* current body has a declared length */
    uint64_t body_left;   /* remaining bytes of current body, if known */
    int64_t pos;          /* logical stream position */
    /* stats */
    uint64_t bytes_read;
    unsigned requests, reconnects;
    unsigned reconnect_budget;
};

static const char *k_probe_range = "Range: bytes=0-0";

const char *rt_strerror(int s) {
    switch (s) {
    case RT_OK: return "ok";
    case RT_ERR_NETWORK: return "network I/O failure";
    case RT_ERR_PROTOCOL: return "protocol violation";
    case RT_ERR_NOT_SEEKABLE: return "resource is not seekable (ranges refused)";
    case RT_ERR_RANGE_REFUSED: return "range resume refused by server";
    case RT_ERR_ENTITY_CHANGED: return "entity changed between ranges";
    case RT_ERR_CANCELLED: return "cancelled by interrupt callback";
    case RT_ERR_RETRY_EXHAUSTED: return "reconnect budget exhausted";
    case RT_ERR_BADARG: return "bad argument";
    default: return "unknown status";
    }
}
const char *rt_version_string(void) {
    return "rt_transport 0.1.0 (W-0286/195b-B7)";
}

/* strict decimal u64: rejects sign, junk, overflow */
static bool parse_u64(const char *s, uint64_t *out) {
    if (!s || !*s || *s == '-' || *s == '+') return false;
    char *ep = NULL; errno = 0;
    unsigned long long v = strtoull(s, &ep, 10);
    if (errno || !ep || *ep) return false;
    *out = (uint64_t)v; return true;
}

/* overflow-checked signed add */
static bool add_i64(int64_t a, int64_t b, int64_t *out) {
    if ((b > 0 && a > INT64_MAX - b) || (b < 0 && a < INT64_MIN - b)) return false;
    *out = a + b; return true;
}

static void default_sleep(void *opaque, unsigned ms) {
    (void)opaque;
    struct timespec ts = { (time_t)(ms / 1000), (long)(ms % 1000) * 1000000L };
    nanosleep(&ts, NULL);
}

static int interrupted(RTTransport *t) {
    if (t->opts.interrupt && t->opts.interrupt(t->opts.interrupt_opaque))
        return RT_ERR_CANCELLED;
    return RT_OK;
}
static void sleep_ms(RTTransport *t, unsigned ms) {
    if (t->opts.sleep_ms) t->opts.sleep_ms(t->opts.sleep_opaque, ms);
    else default_sleep(NULL, ms);
}

static const char *find_header(const RTWireResponse *r, const char *name) {
    for (size_t i = 0; i < r->n_headers; i++)
        if (strncasecmp(r->headers[i].name, name, 64) == 0)
            return r->headers[i].value;
    return NULL;
}

/* Parse "bytes START-END/TOTAL" (TOTAL may be *). */
static bool parse_content_range(const char *v, uint64_t *start, uint64_t *end,
                                uint64_t *total, bool *total_known) {
    unsigned long long s, e; char tot[32];
    if (!v) return false;
    if (strncasecmp(v, "bytes ", 6) != 0) return false;
    if (sscanf(v + 6, "%llu-%llu/%31s", &s, &e, tot) != 3) return false;
    *start = s; *end = e;
    if (strcmp(tot, "*") == 0) { *total_known = false; *total = 0; }
    else {
        if (!parse_u64(tot, total)) return false;
        *total_known = true;
    }
    /* end == UINT64_MAX would wrap body_left = end-start+1 to 0 (false clean
     * EOF); it also cannot be a valid index into any addressable resource. */
    if (e == UINT64_MAX) return false;
    return e >= s;
}

static void copy_hdr(char *dst, size_t cap, const char *v) {
    if (!v) { dst[0] = 0; return; }
    snprintf(dst, cap, "%s", v);
}

/* Build request header list: caller extras + ours (Range, If-Range). */
static int do_request(RTTransport *t, const char *range_hdr, RTWireResponse *resp) {
    const char *hdrs[16]; size_t n = 0;
    char ifrange[320];
    for (size_t i = 0; i < t->opts.n_extra_headers && n < 13; i++)
        hdrs[n++] = t->opts.extra_headers[i];
    if (range_hdr) hdrs[n++] = range_hdr;
    if (range_hdr && t->etag_known) {
        snprintf(ifrange, sizeof ifrange, "If-Range: %s", t->etag);
        hdrs[n++] = ifrange;
    } else if (range_hdr && t->lm_known) {
        snprintf(ifrange, sizeof ifrange, "If-Range: %s", t->last_modified);
        hdrs[n++] = ifrange;
    }
    int rc = t->wire.request(t->wire.ctx, "GET", t->url, hdrs, n, resp);
    if (rc == 0) t->requests++;
    return rc;
}

static void capture_meta(RTTransport *t, const RTWireResponse *r) {
    const char *v;
    if ((v = find_header(r, "ETag")))        { t->etag_known = true; copy_hdr(t->etag, sizeof t->etag, v); }
    if ((v = find_header(r, "Last-Modified"))){ t->lm_known = true; copy_hdr(t->last_modified, sizeof t->last_modified, v); }
    if ((v = find_header(r, "Server")))       copy_hdr(t->server, sizeof t->server, v);
}

/* Validate a resume response for stream position pos. */
static int validate_resume(RTTransport *t, const RTWireResponse *r, uint64_t pos) {
    if (r->status == 200) {
        /* Server ignored Range/If-Range: entity changed, or ranges dropped. */
        const char *et = find_header(r, "ETag");
        if (t->etag_known && et && strcmp(et, t->etag) != 0) return RT_ERR_ENTITY_CHANGED;
        return RT_ERR_RANGE_REFUSED;
    }
    if (r->status != 206) return RT_ERR_PROTOCOL;
    uint64_t s, e, tot; bool tot_known;
    if (!parse_content_range(find_header(r, "Content-Range"), &s, &e, &tot, &tot_known))
        return RT_ERR_PROTOCOL;
    if (s != pos) return RT_ERR_PROTOCOL;
    if (tot_known && e >= tot) return RT_ERR_PROTOCOL; /* end past last valid index */
    if (tot_known && t->size_known && tot != t->size) return RT_ERR_ENTITY_CHANGED;
    const char *et = find_header(r, "ETag");
    if (t->etag_known && et && strcmp(et, t->etag) != 0) return RT_ERR_ENTITY_CHANGED;
    return RT_OK;
}

/* Open a body-bearing exchange at position pos (pos==size allowed: empty read). */
static int open_stream(RTTransport *t, uint64_t pos) {
    char range[64];
    const char *rh = NULL;
    if (t->range_supported) {
        snprintf(range, sizeof range, "Range: bytes=%llu-", (unsigned long long)pos);
        rh = range;
    } else if (pos > 0) {
        return RT_ERR_RANGE_REFUSED; /* cannot resume a non-seekable stream */
    }
    RTWireResponse resp;
    int rc = interrupted(t); if (rc) return rc;
    rc = do_request(t, rh, &resp);
    if (rc) return RT_ERR_NETWORK;
    if (!t->range_supported) {
        if (resp.status != 200) return RT_ERR_PROTOCOL;
        capture_meta(t, &resp);
        const char *cl = find_header(&resp, "Content-Length");
        if (cl) {
            if (!parse_u64(cl, &t->body_left)) return RT_ERR_PROTOCOL;
            t->body_known = true;
        } else { t->body_known = false; t->body_left = 0; }
    } else {
        rc = validate_resume(t, &resp, pos);
        if (rc) { t->wire.close(t->wire.ctx); return rc; }
        capture_meta(t, &resp);
        uint64_t s, e, tot; bool tk;
        parse_content_range(find_header(&resp, "Content-Range"), &s, &e, &tot, &tk);
        t->body_known = true; t->body_left = e - s + 1;
    }
    t->exchange_open = true;
    return RT_OK;
}

/* Reconnect after a drop: bounded retries with backoff, entity validated. */
static int reconnect(RTTransport *t) {
    for (unsigned k = 0; k < t->reconnect_budget; k++) {
        int rc = interrupted(t); if (rc) return rc;
        { /* bounded exponential backoff: 50ms * 2^k, shift capped (no UB
             at k>=32), sleep capped at 60s */
            unsigned shift = k < 11 ? k : 11;
            unsigned long ms = 50UL << shift;
            if (ms > 60000UL) ms = 60000UL;
            sleep_ms(t, (unsigned)ms);
        }
        t->wire.close(t->wire.ctx);
        t->exchange_open = false;
        rc = open_stream(t, (uint64_t)t->pos);
        if (rc == RT_OK) { t->reconnects++; return RT_OK; }
        if (rc == RT_ERR_ENTITY_CHANGED || rc == RT_ERR_CANCELLED) return rc;
        /* NETWORK / RANGE_REFUSED / PROTOCOL: keep retrying within budget */
    }
    return RT_ERR_RETRY_EXHAUSTED;
}

int rt_open(RTTransport **out, const RTWire *wire, const char *url,
            const RTOptions *opts) {
    if (!out || !wire || !wire->request || !wire->recv || !wire->close || !url)
        return RT_ERR_BADARG;
    RTTransport *t = calloc(1, sizeof *t);
    if (!t) return RT_ERR_NETWORK;
    t->wire = *wire;
    t->url = strdup(url);
    if (opts) {
        t->opts = *opts;
    }
    if (t->opts.max_read_chunk == 0) t->opts.max_read_chunk = 65536;
    t->reconnect_budget = t->opts.max_reconnects ? t->opts.max_reconnects : 5;

    /* probe */
    RTWireResponse resp;
    int rc = interrupted(t); if (rc) { rt_close(t); return rc; }
    rc = do_request(t, k_probe_range, &resp);
    if (rc) { int cr = interrupted(t); rt_close(t); return cr ? cr : RT_ERR_NETWORK; }
    if (resp.status == 206) {
        uint64_t s, e, tot; bool tk;
        if (!parse_content_range(find_header(&resp, "Content-Range"), &s, &e, &tot, &tk)
            || s != 0 || e != 0) { rt_close(t); return RT_ERR_PROTOCOL; }
        t->range_supported = true;
        if (tk) { t->size_known = true; t->size = tot; }
        capture_meta(t, &resp);
        t->wire.close(t->wire.ctx); /* discard the 1 probe body byte */
    } else if (resp.status == 200) {
        t->range_supported = false;
        capture_meta(t, &resp);
        const char *cl = find_header(&resp, "Content-Length");
        if (cl) {
            if (!parse_u64(cl, &t->size)) { rt_close(t); return RT_ERR_PROTOCOL; }
            t->size_known = true;
        }
        /* keep this exchange: body starts at 0 */
        t->exchange_open = true;
        if (t->size_known) { t->body_known = true; t->body_left = t->size; }
    } else {
        rt_close(t);
        return RT_ERR_PROTOCOL;
    }
    t->pos = 0;
    *out = t;
    return RT_OK;
}

int rt_get_capabilities(const RTTransport *t, RTCapabilities *out) {
    if (!t || !out) return RT_ERR_BADARG;
    memset(out, 0, sizeof *out);
    out->range_supported = t->range_supported;
    out->size_known = t->size_known; out->size = t->size;
    out->etag_known = t->etag_known; copy_hdr(out->etag, sizeof out->etag, t->etag_known ? t->etag : NULL);
    out->last_modified_known = t->lm_known; copy_hdr(out->last_modified, sizeof out->last_modified, t->lm_known ? t->last_modified : NULL);
    copy_hdr(out->server, sizeof out->server, t->server);
    out->bytes_read = t->bytes_read;
    out->requests = t->requests; out->reconnects = t->reconnects;
    return RT_OK;
}

ptrdiff_t rt_read(RTTransport *t, uint8_t *buf, size_t len) {
    if (!t || !buf) return RT_ERR_BADARG;
    if (len == 0) return 0;
    if (len > t->opts.max_read_chunk) len = t->opts.max_read_chunk; /* backpressure window */
    for (;;) {
        int rc = interrupted(t); if (rc) return rc;
        if (!t->exchange_open) {
            if (t->size_known && (uint64_t)t->pos >= t->size) return 0;
            rc = open_stream(t, (uint64_t)t->pos);
            if (rc == RT_ERR_NETWORK) { /* transient: spend reconnect budget */
                rc = reconnect(t);
                if (rc) return rc;
            } else if (rc) return rc;
        }
        size_t want = len;
        if (t->body_known && want > t->body_left) want = (size_t)t->body_left;
        if (want == 0) { /* declared body done */
            t->wire.close(t->wire.ctx); t->exchange_open = false;
            return 0;
        }
        ptrdiff_t n = t->wire.recv(t->wire.ctx, buf, want);
        if (n > 0) {
            t->pos += n; t->bytes_read += (uint64_t)n;
            if (t->body_known) t->body_left -= (uint64_t)n;
            return n;
        }
        /* n == 0: wire reports framing-complete end of THIS response body
         * (Content-Length satisfied / chunked terminator / close-delimited
         * end). n < 0: hard failure mid-body. Both justify resume only when
         * the declared size says more bytes exist; an unknown-size body
         * ending is clean (HTTP gives no way to detect its mid-body drop:
         * recorded limitation). */
        bool premature = t->size_known && (uint64_t)t->pos < t->size;
        t->wire.close(t->wire.ctx); t->exchange_open = false;
        if (!premature) return 0;
        rc = reconnect(t);
        if (rc) return rc;
        /* loop: reopen and continue */
    }
}

int64_t rt_seek64(RTTransport *t, int64_t off, int whence) {
    if (!t) return RT_ERR_BADARG;
    if (whence == RT_SEEK_SIZE)
        return t->size_known ? (int64_t)t->size : RT_ERR_NOT_SEEKABLE;
    int64_t target;
    switch (whence) {
    case SEEK_SET: target = off; break;
    case SEEK_CUR:
        if (!add_i64(t->pos, off, &target)) return RT_ERR_BADARG;
        break;
    case SEEK_END:
        if (!t->size_known) return RT_ERR_NOT_SEEKABLE;
        if (t->size > (uint64_t)INT64_MAX) return RT_ERR_BADARG; /* unrepresentable */
        if (!add_i64((int64_t)t->size, off, &target)) return RT_ERR_BADARG;
        break;
    default: return RT_ERR_BADARG;
    }
    if (target < 0) return RT_ERR_BADARG;
    if (t->size_known && (uint64_t)target > t->size) return RT_ERR_BADARG;
    if (target == t->pos) return t->pos; /* no-op works even unseekable */
    if (!t->range_supported) return RT_ERR_NOT_SEEKABLE;
    t->wire.close(t->wire.ctx); t->exchange_open = false;
    t->pos = target;
    return t->pos;
}

int64_t rt_tell(const RTTransport *t) { return t ? t->pos : RT_ERR_BADARG; }

void rt_close(RTTransport *t) {
    if (!t) return;
    if (t->exchange_open) t->wire.close(t->wire.ctx);
    free(t->url);
    free(t);
}

```

```text id=kit7
/* rt_transport.h - HTTP range transport provider core (relay/torrent class).
 * W-0286 / 195b-B7. Portable C11, no external dependencies.
 *
 * Sits above a caller-supplied wire backend (one HTTP exchange at a time)
 * and exposes avformat-shaped read/seek/interrupt semantics plus
 * capability reporting. The avformat binding itself is a pinned ABI in
 * rt_avformat_adapter.h (proposed; see RESULT-PACKET.md BLOCKED_INPUT).
 */
#ifndef RT_TRANSPORT_H
#define RT_TRANSPORT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h> /* ptrdiff_t on strict C11 targets */

#ifdef __cplusplus
extern "C" {
#endif

#define RT_VERSION_MAJOR 0
#define RT_VERSION_MINOR 1
#define RT_VERSION_PATCH 0

/* whence extension mirroring avformat AVSEEK_SIZE: query size without seeking */
#define RT_SEEK_SIZE 0x10000

/* typed status codes; negative = error */
typedef enum RTStatus {
    RT_OK                   =  0,
    RT_ERR_NETWORK          = -1, /* wire-level I/O failure */
    RT_ERR_PROTOCOL         = -2, /* malformed HTTP / contract violation */
    RT_ERR_NOT_SEEKABLE     = -3, /* seek requested, ranges not supported */
    RT_ERR_RANGE_REFUSED    = -4, /* server stopped honoring ranges on resume */
    RT_ERR_ENTITY_CHANGED   = -5, /* ETag/Last-Modified/total changed under us */
    RT_ERR_CANCELLED        = -6, /* interrupt callback fired */
    RT_ERR_RETRY_EXHAUSTED  = -7, /* reconnect budget spent */
    RT_ERR_BADARG           = -8  /* bad API argument */
} RTStatus;

const char *rt_strerror(int status);
const char *rt_version_string(void);

#define RT_MAX_RESP_HEADERS 32
typedef struct RTWireResponse {
    int status; /* e.g. 200, 206, 416 */
    struct { char name[64]; char value[256]; } headers[RT_MAX_RESP_HEADERS];
    size_t n_headers;
} RTWireResponse;

/* Wire ABI: exactly one exchange in flight per RTWire instance.
 * request() opens an exchange and fills the parsed response head.
 * recv() reads response-body bytes (0 = end of THIS response body, <0 = wire error).
 * close() ends the exchange; request() implicitly closes any open exchange.
 * recv must never return more than len bytes; the engine uses len as its
 * backpressure window.
 */
typedef struct RTWire {
    void *ctx;
    int (*request)(void *ctx, const char *method, const char *url,
                   const char *const *req_headers, size_t n_req_headers,
                   RTWireResponse *resp);
    ptrdiff_t (*recv)(void *ctx, uint8_t *buf, size_t len);
    void (*close)(void *ctx);
} RTWire;

typedef int  (*RTInterruptFn)(void *opaque); /* !=0 means cancel, avformat AVIOInterruptCB shape */
typedef void (*RTSleepFn)(void *opaque, unsigned ms);

typedef struct RTOptions {
    size_t max_read_chunk;    /* backpressure window: max bytes per recv (0 = 65536) */
    unsigned max_reconnects;  /* resume attempts per drop (0 = 5) */
    RTInterruptFn interrupt; void *interrupt_opaque; /* NULL = never cancelled */
    RTSleepFn sleep_ms; void *sleep_opaque;          /* NULL = nanosleep */
    const char *const *extra_headers; size_t n_extra_headers; /* e.g. caller auth */
} RTOptions;

/* Capability + live-stats snapshot. */
typedef struct RTCapabilities {
    bool range_supported;       /* probe got 206 + valid Content-Range */
    bool size_known;
    uint64_t size;
    bool etag_known;
    char etag[160];
    bool last_modified_known;
    char last_modified[96];
    char server[128];           /* Server header, "" if absent */
    /* live counters */
    uint64_t bytes_read;
    unsigned requests;
    unsigned reconnects;
} RTCapabilities;

typedef struct RTTransport RTTransport;

/* Opens and probes the resource (GET + Range: bytes=0-0). Never streams
 * body past the probe. */
int  rt_open(RTTransport **out, const RTWire *wire, const char *url,
             const RTOptions *opts);
/* Snapshot of capabilities and counters. */
int  rt_get_capabilities(const RTTransport *t, RTCapabilities *out);
/* Stream read at the logical position. Returns bytes read (0 = clean EOF
 * at declared size) or a negative RTStatus. Reconnect/resume is internal. */
ptrdiff_t rt_read(RTTransport *t, uint8_t *buf, size_t len);
/* whence: SEEK_SET / SEEK_CUR / SEEK_END / RT_SEEK_SIZE. Returns new
 * logical position (or size) or negative RTStatus. */
int64_t rt_seek64(RTTransport *t, int64_t off, int whence);
int64_t rt_tell(const RTTransport *t);
void rt_close(RTTransport *t);

#ifdef __cplusplus
}
#endif
#endif /* RT_TRANSPORT_H */

```

```text id=kit8
#define _GNU_SOURCE
#include "rt_wire_posix.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <strings.h>
#include <unistd.h>
#include <errno.h>
#include <netdb.h>
#include <poll.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/time.h>

typedef struct {
    int fd;
    unsigned timeout_ms;
    unsigned connect_timeout_ms;
    RTInterruptFn interrupt; void *interrupt_opaque;
    /* body framing */
    int chunked;
    int64_t cl_left;      /* -1 = until close */
    uint64_t chunk_left;  /* remaining in current chunk */
    int chunk_tail;       /* expect CRLF after chunk */
    /* header read buffer */
    char hbuf[8192];
    size_t hlen, hpos;
} PWire;

static void p_close(void *v) {
    PWire *p = v;
    if (p && p->fd >= 0) { close(p->fd); p->fd = -1; }
}

static ssize_t read_some(PWire *p, char *buf, size_t len) {
    ssize_t n = recv(p->fd, buf, len, 0);
    return n; /* 0 close, <0 error/timeout */
}

/* Body read honoring bytes already buffered during header parsing. */
static ssize_t read_body(PWire *p, char *buf, size_t len) {
    if (p->hpos < p->hlen) {
        size_t avail = p->hlen - p->hpos;
        if (len > avail) len = avail;
        memcpy(buf, p->hbuf + p->hpos, len);
        p->hpos += len;
        return (ssize_t)len;
    }
    return read_some(p, buf, len);
}

/* read one header line (LF terminated; CR stripped only when present).
 * returns 0 ok, 1 overlong (rest of line consumed, content truncated),
 * -1 I/O error. Bare-LF lines keep their full content. */
static int read_line(PWire *p, char *out, size_t cap) {
    size_t n = 0;
    int over = 0;
    for (;;) {
        if (p->hpos < p->hlen) {
            char c = p->hbuf[p->hpos++];
            if (c == '\n') {
                if (n && out[n - 1] == '\r') n--;
                out[n] = 0;
                return over;
            }
            if (n + 1 < cap) out[n++] = c;
            else over = 1; /* keep consuming to stay in framing sync */
        } else {
            ssize_t r = read_some(p, p->hbuf, sizeof p->hbuf);
            if (r <= 0) return -1;
            p->hlen = (size_t)r; p->hpos = 0;
        }
    }
}

static int p_request(void *v, const char *method, const char *url,
                     const char *const *hdrs, size_t n_hdrs,
                     RTWireResponse *resp) {
    PWire *p = v;
    p_close(p);
    /* parse http://host[:port]/path */
    if (strncmp(url, "http://", 7) != 0) return -1;
    const char *hp = url + 7;
    const char *slash = strchr(hp, '/');
    char host[256] = {0}, port[8] = "80";
    const char *colon = slash ? memchr(hp, ':', (size_t)(slash - hp)) : strchr(hp, ':');
    if (colon) {
        snprintf(host, sizeof host, "%.*s", (int)(colon - hp), hp);
        const char *pe = slash ? slash : hp + strlen(hp);
        snprintf(port, sizeof port, "%.*s", (int)(pe - colon - 1), colon + 1);
    } else {
        snprintf(host, sizeof host, "%.*s", slash ? (int)(slash - hp) : (int)strlen(hp), hp);
    }
    const char *path = slash ? slash : "/";

    char portstr[16]; snprintf(portstr, sizeof portstr, "%s", port);
    struct addrinfo hints = {0}, *ai = NULL;
    hints.ai_family = AF_UNSPEC; hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(host, portstr, &hints, &ai) != 0 || !ai) return -1;
    int fd = -1;
    for (struct addrinfo *a = ai; a; a = a->ai_next) {
        fd = socket(a->ai_family, a->ai_socktype, a->ai_protocol);
        if (fd < 0) continue;
        /* bounded connect: non-blocking + poll in 50ms slices so the
         * interrupt callback can fire mid-connect */
        int fl = fcntl(fd, F_GETFL, 0);
        fcntl(fd, F_SETFL, fl | O_NONBLOCK);
        int cr = connect(fd, a->ai_addr, a->ai_addrlen);
        if (cr != 0 && errno == EINPROGRESS) {
            unsigned waited = 0; cr = -1;
            while (waited < p->connect_timeout_ms) {
                if (p->interrupt && p->interrupt(p->interrupt_opaque)) { cr = -2; break; }
                unsigned slice = p->connect_timeout_ms - waited;
                if (slice > 50) slice = 50;
                struct pollfd pfd = { fd, POLLOUT, 0 };
                int pr = poll(&pfd, 1, (int)slice);
                waited += slice;
                if (pr > 0) {
                    int so = 0; socklen_t sl = sizeof so;
                    getsockopt(fd, SOL_SOCKET, SO_ERROR, &so, &sl);
                    cr = so ? -1 : 0;
                    break;
                }
                if (pr < 0 && errno != EINTR) break;
            }
        }
        fcntl(fd, F_SETFL, fl); /* restore blocking */
        if (cr == 0) break;
        close(fd); fd = -1;
        if (cr == -2) break; /* interrupted: stop trying addresses */
    }
    freeaddrinfo(ai);
    if (fd < 0) return -1;
    struct timeval tv = { (time_t)(p->timeout_ms / 1000), (suseconds_t)(p->timeout_ms % 1000) * 1000 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    p->fd = fd;

    /* build request dynamically; fail closed beyond RT_WIRE_MAX_REQUEST */
    size_t need = strlen(method) + strlen(path) + strlen(host) + 64;
    for (size_t i = 0; i < n_hdrs; i++) {
        size_t hl = strlen(hdrs[i]);
        if (hl > RT_WIRE_MAX_REQUEST) { p_close(p); return -1; }
        need += hl + 2;
        if (need > RT_WIRE_MAX_REQUEST) { p_close(p); return -1; }
    }
    char *req = malloc(need);
    if (!req) { p_close(p); return -1; }
    size_t off = 0;
    int w0 = snprintf(req, need, "%s %s HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n",
                      method, path, host);
    if (w0 < 0 || (size_t)w0 >= need) { free(req); p_close(p); return -1; }
    off = (size_t)w0;
    for (size_t i = 0; i < n_hdrs; i++) {
        int wn = snprintf(req + off, need - off, "%s\r\n", hdrs[i]);
        if (wn < 0 || (size_t)wn >= need - off) { free(req); p_close(p); return -1; }
        off += (size_t)wn;
    }
    int wf = snprintf(req + off, need - off, "\r\n");
    if (wf != 2) { free(req); p_close(p); return -1; }
    off += 2;
    size_t sent = 0;
    while (sent < off) {
        ssize_t w = send(fd, req + sent, off - sent, 0);
        if (w <= 0) { free(req); p_close(p); return -1; }
        sent += (size_t)w;
    }
    free(req);

    /* parse response head */
    p->hlen = p->hpos = 0;
    char line[512];
    if (read_line(p, line, sizeof line) != 0) { p_close(p); return -1; } /* overlong status = fail */
    int status = 0;
    if (sscanf(line, "HTTP/%*d.%*d %d", &status) != 1) { p_close(p); return -1; }
    resp->status = status; resp->n_headers = 0;
    for (;;) {
        int lr = read_line(p, line, sizeof line);
        if (lr < 0) { p_close(p); return -1; }
        if (line[0] == 0) break;
        if (lr == 1) continue; /* overlong header: skipped, framing preserved */
        if (resp->n_headers >= RT_MAX_RESP_HEADERS) continue;
        char *c = strchr(line, ':');
        if (!c) continue;
        *c = 0;
        char *val = c + 1; while (*val == ' ') val++;
        snprintf(resp->headers[resp->n_headers].name, 64, "%.63s", line);
        snprintf(resp->headers[resp->n_headers].value, 256, "%.255s", val);
        resp->n_headers++;
    }
    /* framing */
    p->chunked = 0; p->cl_left = -1; p->chunk_left = 0; p->chunk_tail = 0;
    for (size_t i = 0; i < resp->n_headers; i++) {
        if (strncasecmp(resp->headers[i].name, "Transfer-Encoding", 64) == 0 &&
            strcasestr(resp->headers[i].value, "chunked")) p->chunked = 1;
        if (strncasecmp(resp->headers[i].name, "Content-Length", 64) == 0)
            p->cl_left = (int64_t)strtoll(resp->headers[i].value, NULL, 10);
    }
    if (status == 204 || status == 304 || (status >= 100 && status < 200)) p->cl_left = 0;
    return 0;
}

static ptrdiff_t p_recv(void *v, uint8_t *buf, size_t len) {
    PWire *p = v;
    if (p->fd < 0) return -1;
    if (p->chunked) {
        if (p->chunk_tail) { /* consume CRLF after data */
            char crlf[2]; size_t got = 0;
            while (got < 2) {
                ssize_t r = read_body(p, crlf + got, 2 - got);
                if (r <= 0) return -1;
                got += (size_t)r;
            }
            p->chunk_tail = 0;
        }
        while (p->chunk_left == 0) {
            char line[64];
            if (read_line(p, line, sizeof line) != 0) return -1;
            unsigned long cs = strtoul(line, NULL, 16);
            if (cs == 0) { p_close(p); return 0; } /* last chunk; trailers skipped */
            p->chunk_left = cs;
        }
        if (len > p->chunk_left) len = (size_t)p->chunk_left;
        ssize_t n = read_body(p, (char *)buf, len);
        if (n < 0) return -1;
        if (n == 0) return -1; /* drop inside a chunk */
        p->chunk_left -= (uint64_t)n;
        if (p->chunk_left == 0) p->chunk_tail = 1;
        return n;
    }
    if (p->cl_left == 0) return 0;
    if (p->cl_left > 0 && len > (size_t)p->cl_left) len = (size_t)p->cl_left;
    ssize_t n = read_body(p, (char *)buf, len);
    if (n < 0) return -1;           /* timeout or error: engine decides retry */
    if (n == 0) {
        /* connection closed: clean only for close-delimited bodies */
        return p->cl_left > 0 ? -1 : 0;
    }
    if (p->cl_left > 0) p->cl_left -= n;
    return n;
}

int rt_wire_posix_open_cfg(RTWire *wire, const RTWirePosixConfig *cfg) {
    if (!wire) return -1;
    PWire *p = calloc(1, sizeof *p);
    if (!p) return -1;
    p->fd = -1;
    p->timeout_ms = cfg && cfg->recv_timeout_ms ? cfg->recv_timeout_ms : 5000;
    p->connect_timeout_ms = cfg && cfg->connect_timeout_ms ? cfg->connect_timeout_ms : 5000;
    if (cfg) { p->interrupt = cfg->interrupt; p->interrupt_opaque = cfg->interrupt_opaque; }
    wire->ctx = p;
    wire->request = p_request;
    wire->recv = p_recv;
    wire->close = p_close;
    return 0;
}

int rt_wire_posix_open(RTWire *wire, unsigned recv_timeout_ms) {
    RTWirePosixConfig cfg = { recv_timeout_ms, 0, NULL, NULL };
    return rt_wire_posix_open_cfg(wire, &cfg);
}

void rt_wire_posix_free(RTWire *wire) {
    if (!wire || !wire->ctx) return;
    p_close(wire->ctx);
    free(wire->ctx);
    wire->ctx = NULL;
}

```

```text id=kit9
/* rt_wire_posix.h - minimal blocking HTTP/1.1 wire backend (synthetic use).
 * http:// URLs only, Connection: close per exchange, chunked decode included.
 * Request line+headers are built dynamically (cap RT_WIRE_MAX_REQUEST);
 * oversized requests fail closed. Connect is bounded by a timeout and an
 * optional interrupt callback. Not a production HTTP stack (see
 * RESULT-PACKET.md limits). */
#ifndef RT_WIRE_POSIX_H
#define RT_WIRE_POSIX_H
#include "rt_transport.h"

/* hard cap on a serialized request (request line + all headers) */
#define RT_WIRE_MAX_REQUEST 16384

typedef struct RTWirePosixConfig {
    unsigned recv_timeout_ms;    /* 0 = 5000 */
    unsigned connect_timeout_ms; /* 0 = 5000 */
    RTInterruptFn interrupt;     /* checked during connect; NULL = none */
    void *interrupt_opaque;
} RTWirePosixConfig;

int rt_wire_posix_open_cfg(RTWire *wire, const RTWirePosixConfig *cfg);
/* compat wrapper: recv timeout only, 5s connect, no wire-level interrupt */
int rt_wire_posix_open(RTWire *wire, unsigned recv_timeout_ms);

/* close any exchange and free the wire context. Callers own this. */
void rt_wire_posix_free(RTWire *wire);

#endif

```

```text id=kit10
/* e2e_client.c - drives rt_transport over the posix wire against the
 * synthetic python server. Modes:
 *   e2e_client URL full <len>      read all, verify generator bytes
 *   e2e_client URL seek <len>      200 pseudo-random seeks + verifies
 *   e2e_client URL cancel <k>      interrupt after k bytes; expect CANCELLED
 * Prints one "E2E <mode> ..." verdict line and machine-readable stats. */
#include "../src/rt_transport.h"
#include "../src/rt_wire_posix.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint8_t expect_byte(uint64_t i) { return (uint8_t)(i * 131u + 17u); }

static uint64_t g_seen; static uint64_t g_cancel_at;
static int interrupt_cb(void *o) { (void)o; return g_seen >= g_cancel_at; }

int main(int argc, char **argv) {
    if (argc < 4) { fprintf(stderr, "usage\n"); return 2; }
    const char *url = argv[1], *mode = argv[2];
    long arg = strtol(argv[3], NULL, 10);

    RTWire wire;
    RTOptions o = {0};
    if (strcmp(mode, "cancel") == 0) {
        o.interrupt = interrupt_cb; g_cancel_at = (uint64_t)arg;
        /* wire-level interrupt plumbed too (connect-time cancel path) */
        RTWirePosixConfig cfg = { 5000, 5000, interrupt_cb, NULL };
        if (rt_wire_posix_open_cfg(&wire, &cfg) != 0) { printf("E2E %s FAIL wire\n", mode); return 1; }
    } else {
        if (rt_wire_posix_open(&wire, 5000) != 0) { printf("E2E %s FAIL wire\n", mode); return 1; }
    }
    RTTransport *t = NULL;
    int rc = rt_open(&t, &wire, url, &o);
    if (rc != RT_OK) { printf("E2E %s FAIL open=%s\n", mode, rt_strerror(rc));
        rt_wire_posix_free(&wire); return 1; }
    RTCapabilities c; rt_get_capabilities(t, &c);
    printf("caps range=%d size_known=%d size=%llu etag=%s server=%s\n",
           c.range_supported, c.size_known, (unsigned long long)c.size,
           c.etag_known ? c.etag : "-", c.server);

    uint8_t buf[16384];
    int ok = 1;
    if (strcmp(mode, "full") == 0) {
        uint64_t got = 0; ptrdiff_t n;
        while ((n = rt_read(t, buf, sizeof buf)) > 0)
            for (ptrdiff_t i = 0; i < n; i++)
                if (buf[i] != expect_byte(got++)) { ok = 0; break; }
        if (n < 0) { printf("E2E full FAIL read=%s\n", rt_strerror((int)n)); return 1; }
        ok = ok && got == (uint64_t)arg;
        printf("E2E full %s bytes=%llu\n", ok ? "PASS" : "FAIL", (unsigned long long)got);
    } else if (strcmp(mode, "seek") == 0) {
        uint32_t st = 12345;
        for (int k = 0; k < 200 && ok; k++) {
            st = st * 1664525u + 1013904223u;
            int64_t pos = (int64_t)(st % (uint32_t)arg);
            if (rt_seek64(t, pos, SEEK_SET) != pos) { ok = 0; break; }
            ptrdiff_t n = rt_read(t, buf, 997);
            int64_t want = arg - pos < 997 ? arg - pos : 997;
            if (n != want) { ok = 0; break; }
            for (ptrdiff_t i = 0; i < n; i++)
                if (buf[i] != expect_byte((uint64_t)pos + (uint64_t)i)) { ok = 0; break; }
        }
        printf("E2E seek %s\n", ok ? "PASS" : "FAIL");
    } else if (strcmp(mode, "cancel") == 0) {
        ptrdiff_t n; g_seen = 0;
        while ((n = rt_read(t, buf, 4096)) > 0) g_seen += (uint64_t)n;
        ok = (n == RT_ERR_CANCELLED);
        printf("E2E cancel %s bytes_before_cancel=%llu\n", ok ? "PASS" : "FAIL",
               (unsigned long long)g_seen);
    } else { printf("E2E unknown mode\n"); return 2; }

    rt_get_capabilities(t, &c);
    printf("stats requests=%u reconnects=%u bytes=%llu\n",
           c.requests, c.reconnects, (unsigned long long)c.bytes_read);
    rt_close(t);
    rt_wire_posix_free(&wire);
    return ok ? 0 : 1;
}

```

```bash id=kit11
#!/bin/sh
# W-0286 e2e: synthetic server + posix-wire client. No real endpoints.
set -u
cd "$(dirname "$0")"
if [ "${RT_SAN:-0}" = 1 ]; then alias_true=1; fi
CLI=./e2e_client; WIRE=./test_wire
if [ "${RT_SAN:-0}" = 1 ]; then CLI=./e2e_client_san; WIRE=./test_wire_san; fi
PORT=8971
python3 synth_server.py $PORT & SRV=$!
sleep 1
F=0
run() { echo "== $*"; "$@" || F=1; }
run $CLI http://127.0.0.1:$PORT/full    full   1048576
run $CLI http://127.0.0.1:$PORT/drop    full   300000
run $CLI http://127.0.0.1:$PORT/dribble full   200000
run $CLI http://127.0.0.1:$PORT/norange full   150000
run $CLI http://127.0.0.1:$PORT/chunked full   120000
run $CLI http://127.0.0.1:$PORT/full    seek   1048576
run $CLI http://127.0.0.1:$PORT/dribble cancel 100000
run $WIRE $PORT
kill $SRV 2>/dev/null
[ $F -eq 0 ] && echo "E2E RESULT: PASS" || echo "E2E RESULT: FAIL"
exit $F

```

```bash id=kit12
#!/bin/sh
# W-0286 e2e: synthetic server + posix-wire client. No real endpoints.
set -u
cd "$(dirname "$0")"
if [ "${RT_SAN:-0}" = 1 ]; then alias_true=1; fi
CLI=./e2e_client; WIRE=./test_wire
if [ "${RT_SAN:-0}" = 1 ]; then CLI=./e2e_client_san; WIRE=./test_wire_san; fi
PORT=8973
python3 synth_server.py $PORT & SRV=$!
python3 - "$PORT" <<'PYEOF'
import socket, sys, time
port = int(sys.argv[1]); deadline = time.monotonic() + 5.0
while True:
    s = socket.socket()
    try:
        s.connect(("127.0.0.1", port)); s.close(); break
    except OSError:
        s.close()
        if time.monotonic() > deadline:
            print("readiness-timeout: synth server not listening after 5.0s", file=sys.stderr)
            sys.exit(2)
        time.sleep(0.1)
PYEOF
F=0
run() { echo "== $*"; "$@" || F=1; }
run $CLI http://127.0.0.1:$PORT/full    full   1048576
run $CLI http://127.0.0.1:$PORT/drop    full   300000
run $CLI http://127.0.0.1:$PORT/dribble full   200000
run $CLI http://127.0.0.1:$PORT/norange full   150000
run $CLI http://127.0.0.1:$PORT/chunked full   120000
run $CLI http://127.0.0.1:$PORT/full    seek   1048576
run $CLI http://127.0.0.1:$PORT/dribble cancel 100000
run $WIRE $PORT
kill $SRV 2>/dev/null
[ $F -eq 0 ] && echo "E2E RESULT: PASS" || echo "E2E RESULT: FAIL"
exit $F

```

```python id=kit13
#!/usr/bin/env python3
"""Synthetic HTTP servers for W-0286 e2e checks. Deterministic content:
byte[i] = (i*131 + 17) & 0xff. No real endpoints involved.

Paths:
  /full     - range-capable (Accept-Ranges: bytes, 206, ETag)
  /drop     - range-capable; first non-range request dies after DROP_AT bytes
  /dribble  - range-capable, 4KB chunks every 20ms (slow relay)
  /norange  - ignores Range, always 200 full body (Accept-Ranges: none)
  /chunked  - ignores Range, Transfer-Encoding: chunked, no Content-Length
"""
import sys, time, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ETAG = '"synth-7f3a"'
LENGTHS = {"/full": 1 << 20, "/drop": 300000, "/dribble": 200000,
           "/norange": 150000, "/chunked": 120000, "/barelf": 50000}
DROP_AT = 200000
dropped_once = set()
lock = threading.Lock()

def gen(n):
    return bytes(((i * 131 + 17) & 0xFF) for i in range(n))

class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass

    def _range(self, length):
        r = self.headers.get("Range")
        if not r: return None
        try:
            spec = r.split("=", 1)[1]
            a, b = spec.split("-", 1)
            start = int(a)
            end = int(b) if b else length - 1
            end = min(end, length - 1)
            if start > end or start >= length: return "invalid"
            return start, end
        except Exception:
            return "invalid"

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path not in LENGTHS:
            self.send_error(404); return
        length = LENGTHS[path]
        rng = self._range(length)
        honor = path in ("/full", "/drop", "/dribble")
        if rng == "invalid" and honor:
            self.send_response(416)
            self.send_header("Content-Range", "bytes */%d" % length)
            self.send_header("Content-Length", "0")
            self.end_headers(); return

        if path == "/barelf":
            # LF-only response lines (no CR) - exercises tolerant line parsing
            body = gen(length)
            raw = ("HTTP/1.1 200 OK\nContent-Length: %d\nServer: synth-barelf\n\n" % length).encode() + body
            self.wfile.write(raw)
            self.close_connection = True
            return

        if path == "/chunked":
            self.send_response(200)
            self.send_header("Transfer-Encoding", "chunked")
            self.send_header("ETag", ETAG)
            self.end_headers()
            data = gen(length)
            for i in range(0, len(data), 8192):
                c = data[i:i+8192]
                self.wfile.write(("%x\r\n" % len(c)).encode() + c + b"\r\n")
            self.wfile.write(b"0\r\n\r\n")
            return

        if honor and rng:
            start, end = rng
            body = gen(length)[start:end + 1]  # slice of the SAME content
            self.send_response(206)
            self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, length))
        else:
            body = gen(length)
            self.send_response(200)
            self.send_header("Accept-Ranges", "none" if path == "/norange" else "bytes")
        self.send_header("ETag", ETAG)
        self.send_header("Last-Modified", "Wed, 11 Nov 2026 00:00:00 GMT")
        self.send_header("Server", "synth/1.0")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()

        full_body = rng is None or rng == (0, length - 1)
        if path == "/drop" and full_body:
            with lock:
                first = path not in dropped_once
                dropped_once.add(path)
            if first:
                self.wfile.write(body[:DROP_AT])
                self.wfile.flush()
                self.connection.shutdown(2)  # hard drop mid-body
                self.connection.close()
                return
        if path == "/dribble":
            for i in range(0, len(body), 4096):
                self.wfile.write(body[i:i+4096]); self.wfile.flush()
                time.sleep(0.02)
            return
        self.wfile.write(body)

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8971
    ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()

```

```text id=kit14
/* test_wire.c - posix-wire regression checks (review F1 + lower findings).
 * Needs the synthetic server on argv[1] for W2/W4; connect checks are local. */
#include "../src/rt_transport.h"
#include "../src/rt_wire_posix.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { \
    printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #cond); failures++; } \
    else printf("ok   %s\n", #cond); } while (0)

static double now_s(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

static int g_arm; static int g_calls;
static int interrupt_armed(void *o) { (void)o; return ++g_calls >= g_arm; }

int main(int argc, char **argv) {
    int port = argc > 1 ? atoi(argv[1]) : 8971;

    /* W1: 20000-char path exceeds RT_WIRE_MAX_REQUEST -> fail closed, no overflow */
    {
        RTWire w; RTWirePosixConfig cfg = { 1000, 1000, NULL, NULL };
        CHECK(rt_wire_posix_open_cfg(&w, &cfg) == 0);
        char url[20200];
        snprintf(url, sizeof url, "http://127.0.0.1:%d/", port);
        size_t base = strlen(url);
        memset(url + base, 'a', 20000); url[base + 20000] = 0;
        RTTransport *t = NULL;
        int rc = rt_open(&t, &w, url, NULL);
        CHECK(rc == RT_ERR_NETWORK && t == NULL);
        rt_wire_posix_free(&w);
    }
    /* W2: 4000-char path fits the dynamic buffer -> request is really sent
     * (server 404s the unknown path; engine reports typed PROTOCOL, no crash) */
    {
        RTWire w; rt_wire_posix_open(&w, 2000);
        char url[4200];
        snprintf(url, sizeof url, "http://127.0.0.1:%d/", port);
        size_t base = strlen(url);
        memset(url + base, 'a', 4000); url[base + 4000] = 0;
        RTTransport *t = NULL;
        int rc = rt_open(&t, &w, url, NULL);
        CHECK(rc == RT_ERR_PROTOCOL && t == NULL);
        rt_wire_posix_free(&w);
    }
    /* W3: 3000-char extra header fits -> normal fetch works byte-exact */
    {
        RTWire w; rt_wire_posix_open(&w, 2000);
        static char big[3001]; memset(big, 'H', 2990); big[2990] = 0;
        memcpy(big, "X-Pad: ", 7);
        const char *hdrs[1] = { big };
        RTOptions o = {0}; o.extra_headers = hdrs; o.n_extra_headers = 1;
        char url[64]; snprintf(url, sizeof url, "http://127.0.0.1:%d/norange", port);
        RTTransport *t = NULL;
        CHECK(rt_open(&t, &w, url, &o) == RT_OK);
        uint8_t b[8192]; size_t got = 0; ptrdiff_t n; int okd = 1;
        while ((n = rt_read(t, b, sizeof b)) > 0)
            for (ptrdiff_t i = 0; i < n; i++)
                if (b[i] != (uint8_t)((got++) * 131u + 17u)) okd = 0;
        CHECK(n == 0 && okd && got == 150000);
        rt_close(t);
        rt_wire_posix_free(&w);
    }
    /* W4: bare-LF response lines parse correctly (read_line CR strip fix) */
    {
        RTWire w; rt_wire_posix_open(&w, 2000);
        char url[64]; snprintf(url, sizeof url, "http://127.0.0.1:%d/barelf", port);
        RTTransport *t = NULL;
        CHECK(rt_open(&t, &w, url, NULL) == RT_OK);
        RTCapabilities c; rt_get_capabilities(t, &c);
        CHECK(c.size_known && c.size == 50000);
        uint8_t b[8192]; size_t got = 0; ptrdiff_t n; int okd = 1;
        while ((n = rt_read(t, b, sizeof b)) > 0)
            for (ptrdiff_t i = 0; i < n; i++)
                if (b[i] != (uint8_t)((got++) * 131u + 17u)) okd = 0;
        CHECK(n == 0 && okd && got == 50000);
        rt_close(t);
        rt_wire_posix_free(&w);
    }
    /* W5: connect timeout bounds an unreachable host */
    {
        RTWire w; RTWirePosixConfig cfg = { 500, 300, NULL, NULL };
        rt_wire_posix_open_cfg(&w, &cfg);
        RTTransport *t = NULL;
        double t0 = now_s();
        int rc = rt_open(&t, &w, "http://10.255.255.1:8971/x", NULL);
        double dt = now_s() - t0;
        CHECK(rc == RT_ERR_NETWORK);
        CHECK(dt < 10.0);
        printf("info connect-timeout path took %.2fs\n", dt);
        rt_wire_posix_free(&w);
    }
    /* W6: wire-level interrupt aborts a stuck connect */
    {
        RTWire w; g_arm = 3; g_calls = 0;
        RTWirePosixConfig cfg = { 500, 30000, interrupt_armed, NULL };
        rt_wire_posix_open_cfg(&w, &cfg);
        RTTransport *t = NULL;
        double t0 = now_s();
        int rc = rt_open(&t, &w, "http://10.255.255.1:8971/x", NULL);
        double dt = now_s() - t0;
        CHECK(rc != 0 && t == NULL);
        CHECK(dt < 10.0);
        printf("info connect-interrupt path took %.2fs\n", dt);
        rt_wire_posix_free(&w);
    }

    printf(failures ? "WIRE RESULT: FAIL (%d)\n" : "WIRE RESULT: PASS\n", failures);
    return failures ? 1 : 0;
}

```

```text id=actual_run_log
PASS carrier-integrity
PASS build
PASS mutant-A-no-server (exactly the 6 observed sites)
PASS mutant-B-fixed-e2e
b7-transport-flake: 4/4 checks PASS
```
