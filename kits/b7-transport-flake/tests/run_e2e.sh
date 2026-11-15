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
