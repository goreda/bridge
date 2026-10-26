# Native inspection tooling

These tools may be run. Their results are labeled author reported until re-run on the tip under test. The fontTools dependency/version pin remains OPEN; do not install silently. The delivery gate lives in `delivery/`.

After explicit execution permission and parser pin: independently inspect an actual generated font with verify_cff_font.py, then compare caller-authored source JSON with compare_decoded_outline.py. Require .notdef and all expected sibling glyphs and cmap/metric/line/cubic point/control/closure sequences. JSON normalizes numbers but initial exact signed16 integer domain remains preserved; no float tolerance/scale conversion introduced. Exact operator equality may reject harmless alternate pen output, never silently accept missing geometry. Do not normalize away explicit closure or reversed contours. Actual pixels/native editor acceptance is still a separate required stage.

The comparator is not a reconstruction accuracy score and does not test fitting. It checks supplied-outline serialization identity only. Negative comparison fixtures should cover lost siblings/missing controls/reversed contours/incorrect cmap/metrics. No PASS log is filed for the comparator.
