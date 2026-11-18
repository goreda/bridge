# 199h independent replay

Swift 6.0.3 Linux, explicit -Onone and -O. Source-only patches extracted from each packet markdown apply without repair and reproduce the corresponding fixed materialized bytes exactly. All 113 listed carrier file digests match. No refs changed. This is engineering evidence, not owner approval.

All ten baselines compile and run RED; all fixed sources compile and run GREEN. A35 baseline traps (-4) in both modes; other baselines fail assertions. Every row has a compiling production mutant that runs RED. Each supplied fixed test contains two checks except A33, which contains three.

Correction to initial progress: A35's first mutant removed only the usableEnd representability guard and SURVIVED because the later raw-position guard still refused the input. This survivor is retained. A35 mutant2 removes both Int-range guards and traps (-4) in both modes. Other selected mutants fail assertions. See RESULTS.json and exact mutation script/source files.

## Extra boundaries, both modes

- A31: filtering greatestFiniteMagnitude then its negative, with ordinary finite time/tuning, produces negative infinity. Invalid-time history holding works in the added control. The patch stops explicit nonfinite inputs but does not ensure derived finite arithmetic.
- A33: Linux Foundation rejects the bracketed IPv6 loopback form http://[::1]:2222/a in the current predicate, because its host does not match the literal ::1 expected by the implementation. LOCALHOST succeeds. Uppercase HTTP also rejects. These are normalization/compatibility findings, not remote-host admissions; native Foundation behavior is NOT_RUN.
- A36: the fixed empty-vars path traps (-4) on greatestFiniteMagnitude size. The quarter-bucket fix adds a multiply/conversion hazard to that branch. The caller domain may rule extreme sizes out, but this is not arbitrary-finite-input safe.
- A40: two finite CPU values 1.7e308 sum to infinity. Reachable parent cycles terminate. The closure fix does not validate aggregate finiteness. Actual process CPU values are normally bounded far below this synthetic input.
- A38: single-encoded dot, dotdot, slash and backslash reject; double-encoded dotdot and encoded NUL admit. No claim of an exploitable traversal without a demonstrated second decoder. Ordinary nested paths and encoded spaces remain accepted.
- A32: negative read refuses without consuming data; following positive read returns exactly [1,2,3], EOF throws.
- A34: actual supported schemes and uppercase HTTPS accepted, scheme lookalikes and missing hosts refused.
- A35: nonfinite/negative/zero duration refused; finite near-Int durations safely produce representable positions when the sampled range permits them; malformed margins refused.
- A37: control characters, quotes, backslash, Japanese text and emoji roundtrip as JSON data; min/max integer arguments preserve string form.
- A39: option-looking, spaces/newlines, empty and dash-only paths remain a separate argument after the terminator. No real mpv process invoked.

Raw argv, compiler logs, runtime logs, selected verbatim production declarations, complete source, exact configs, patch application checks, mutation sources and boundary mains are included. Native application, camera, IPC, network, process launch, UI and font rendering are NOT_RUN. Returned helper wrappers and supports are preserved, not claimed as full-host builds. A31-34/37/38 are defensive hardening; A35/36/39/40 original defect classification is not expanded to observed incidents by these tests.
