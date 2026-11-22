#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# Current store-applier lifecycle, real extracted methods, explicit boundary spies.
python3 "$HERE/current_route.py"
GOR_VR_TEST_NO_CAMERA=1 python3 "$HERE/current_route.py"
GOR_VR_SIM_POSE=1 python3 "$HERE/current_route.py"
python3 "$HERE/blink_gesture_replay_test.py"
# Actual production recognizer compiled, separate from the replay model.
sh "$HERE/../BlinkRecognizer/run.sh"
