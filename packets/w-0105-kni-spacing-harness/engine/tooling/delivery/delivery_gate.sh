#!/bin/sh
# Required production handoff gate: no ready receipt on numerical or visual failure.
set -eu
if [ "$#" -ne 8 ]; then
 echo 'usage: delivery_gate.sh FONT MANIFEST VECTOR_RECEIPT REFERENCE_FONT_SHA256 EVIDENCE_DIR PPEM THRESHOLD VISUAL_REVIEW_JSON' >&2; exit 2
fi
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
python3 "$here/delivery_gate.py" --font "$1" --manifest "$2" --vector-receipt "$3" --reference-font-sha256 "$4" --output "$5" --ppem "$6" --threshold "$7"
python3 "$here/seal_evidence.py" --pack "$5" --review "$8" --output "$5/delivery-ready.json"
