## Material correction: SHARP versus grain, November 17 00:45 +03

Live build remains 6afb731d / carrier 8b91b96. Lane b corrects the shader roles: bc9a2a32 is combined SHARP Phase2; aa949d3b is spatial-only SHARP and synthesizes no grain. Linux proof establishes sharp bypass, not the cause of the owner's no-grain symptom. Any prior wording here calling these grain or treating aa949d3b as grain fallback is superseded. Grain causality is NOT_PROVEN.

Sharp must fall back to aa949d3b on failure; grain must stay on its separate proven grain shader and preserve its entry after every shared-list set. Require error-to-shader association and a no-recursion latch, failure hash/state/HUD. Native shipped-path witness reports actual grain shader hash, parse/compile and independent grain-only output delta, separate from sharp-fallback delta. Deliberately corrupt fixture must prove sharp fallback plus non-zero grain delta; sharp output cannot stand in for grain synthesis. The gate now checks these roles separately and refuses zero grain delta, wrong grain role, missing grain entry or absent recursion guard. Tests are synthetic validator checks, not execution proof. Guard remains a named diff on delivered 15acf95c, independent of incomplete v4. No native grain or sharp runtime acceptance exists yet.

# Delivered feature gate and acceptance map

Owner-verified capability rows: 0. Capability rows moved since the previous wake: 0. M1 delivered: no.

Owner sources: arch-198f, phonemsg-01M7K1G2HNK7WB49MP39B6583T; correction arch-198g, phonemsg-01M7K1J2TWFQ97D6HENP27MAW6. A candidate is delivered baseline 15acf95c plus explicit named diffs. No delivery feature is removed, stubbed or disabled to pass a compile.

| Requirement | Current evidence | Remaining gate |
| --- | --- | --- |
| 198f item 2: baseline | DELIVERED-BASELINE.json hashes all 1,744 files in the exact delivered source manifest, including 158 Resources files, input.conf bindings, static Lua registrations, Swift menu/panel source entries and injected photon shader names. | Generated bundle hashes and dynamic UI entries require a successful built artifact and runtime witness. This is not full item 2 acceptance. |
| Item 3: loss detector | Source checks find no removed Resources or static registrations in 6c1a or the WT/sharp candidate. | Blocking comparison must use the built app and its actual resolved resource closure. Missing feature fails unless verified owner instruction exists in REMOVALS.md. A deliberate removal test is required. Atomic leased delivery push must consume this exact result. |
| Item 4: update and rollback | Requested in bridge W-gdb-ops-198f-04. | Production build.sh refuses before swapping, keeps current app/state, backs up complete prior app and state, and restores both on rollback. Actual refusal transcript and state-hash test required. |
| Item 5: Darwin smoke | Requested in bridge W-gdb-ops-198f-05. | All photon Lua loads, grain/sharp shader compilation and glsl-shaders membership, script-message round trip, raw log. No native result supplied. |
| Item 6, corrected by 198g | Exact 6c1a source Resources are byte-equal to 15acf95c. Carrier 4ea7f4f failed Darwin compilation, so it produced no verified final built app inventory. | Successful artifact and packaging evidence remain required. No photon restoration claim applies to 6c1a. |

## Packaging contract that the checker must cover

Both delivered 15acf95c and candidate 6c1a build.sh keep vendor and fonts outside the app. The linking-resources block checks sibling project Resources/vendor and Resources/fonts. The runtime resolver loads them from that external closure; photon Lua is not copied into Contents/Resources by that block. This existing layout is not changed by the gate. A bundle-only file comparison would miss removal from that external resource closure, so the gate must inventory the built app plus the resources actually resolved by that app. Source-only presence cannot substitute for it. Until resolved closure and runtime semantic evidence are available, the gate remains incomplete and delivery is blocked.

The existing manifest regeneration, zero-mismatch updater integrity, production preinstall regression, architecture checks and actual exact native PASS remain required. Neither a static registry PASS nor a compile-only PASS establishes this whole gate. A delivery that switches playback to gorav additionally requires photon parity on the gorav path.

## Executable checker, first implementation

`bundle-feature-gate.py --baseline DELIVERED-BASELINE.json --bundle CANDIDATE.app --resources RESOLVED/Resources --installed INSTALLED.app --installed-resources INSTALLED/Resources --runtime feature-runtime.json --removals REMOVALS.md --out report.json`

This implementation compares actual resource presence, bindings, registrations, injected shader names, app file presence and runtime menu/panel/shader feature lists bound to the exact executable SHA256. The baseline is deliberately source-only today, so the production baseline always refuses until the delivered built-bundle inventory and runtime feature manifest are attested. This is intentional fail-closed behavior, not gate completion. REMOVALS.md grants nothing by itself. The checker accepts only the four exact internal G1-G4 transport names mapped to the recovered arch-198d owner instruction, with no file/binding/menu/shader exemption. These stricter open gates must not be described as accepted exemptions.

`python3 docs/delivery/test-bundle-feature-gate.py` proves one complete synthetic closure case and expected refusal on missing file, binding, registration, shader, menu, mismatched executable and unattested baseline. See removal-mutant-test.log. These are checker regression fixtures, not production build.sh or actual Darwin smoke acceptance. The next baseline witness must build and run 15acf95c, capture full built/external closure and actual menu/panel/message/shader registrations; source-line inventories cannot stand in for it.

## Atomic leased promotion entry point

`atomic-delivery-push.py` requires an exact candidate proof containing named diffs, delivered-baseline ancestry, exact Darwin compile, regenerated manifest, updater zero mismatches, preinstall and photon smoke PASS. It reruns the built app plus sibling Resources checker in the same process before checking current delivery refs and issuing one atomic leased push. Default is dry run; `--execute` is explicit. The current source-only baseline and missing runtime/build evidence refuse promotion. It is not a substitute for verifying the user's authority or inspecting evidence authenticity. Parent owns the same-turn owner update and changelog. No live promotion was attempted.

Owner instruction phonemsg-01M7K1TQ0TGZFEHX5VQMM7QDM7, November 16 at 23:47:25, says "disk maliyeti çıkarmadan aynen devam işte." Keep existing sibling vendor/fonts packaging unchanged, without copying it into the app or adding disk cost. The gate reads both app and resolved sibling Resources.

## 198j no-silent-bypass requirement

Owner original phonemsg-01M7K51VZ913EFXSKAXFH5K652, November 17 00:43 +03. The next photon-containing owner delivery must include the Lua/Swift no-silent-bypass mechanism with spatial fallback aa949d3bf1eb4812c32589121e8f046ec6951f82c563270f4c91efa3b9312bdb. Do not wait for full v4. The current code does not implement that mechanism; this section and checker require its actual native evidence.

Runtime JSON now requires photon_no_silent_bypass on any photon resource closure. Its result must PASS and bind executable_sha256 plus resource_files_sha256 (SHA256 of UTF-8 json.dumps of actual relative-path-to-file-SHA map, sort_keys=True, separators=(',',':')). The shipped_path object names exact baseline source_pin 15acf95c full SHA, Darwin platform, actual mpv_sha256, vo, gpu_api and mpv_conf_sha256. Use the binary and effective config/backend the delivered bundle actually ships, not a convenient separate mpv installation.

The harness supplies all_photon_shader_hashes and an exactly covering shader_results table with shader_sha256, parse_ok, compile_ok and max_delta_from_bypass. Include delivered combined Phase2 bc9a2a32e522a600cc24f08686f47932ba376eb7d99f79dfdd9beffe17c0ee8a even if rejected. Also capture glsl_shaders_after_load, changing_frame_fixture_sha256, explicit history_result (PREVIOUS_FRAME_PROVEN, CURRENT_FRAME_REUSE or NOT_PROVEN) and lua_swift_twins PASS. A failure result for original Phase2 is not hidden: a functioning spatial fallback can permit the no-bypass mechanism while true temporal history remains unproven, never falsely accepted.

corrupt_shader_fixture must show deliberately_corrupt, parse_failed, fallback_engaged, warn_error_subscription, effective_shader_list_verified, state_failure_hash_recorded, hud_failure_shown and fallback_active_in_shader_list all true. It must name the exact spatial fallback SHA above, record raw_log_sha256 and a measured max_delta_from_bypass greater than zero. Zero delta, missing fallback or missing failure notice/state evidence refuses delivery. Grain and sharp subscribe to mpv warn/error logs and verify effective glsl-shaders after every shader set; parser failure or missing entry must switch at once, persist failed shader hash in state and show HUD failure. Grain on must never silently become bypass.

Receipt validation is not runtime execution authentication. Ops must inspect actual native raw logs, shipped-path identity, complete shader inventory and fixture result before accepting these fields. Synthetic validator tests establish only fail-closed schema behavior. No real Darwin receipt exists today. The native parser/delta table, corrupt fallback and changing-frame history are folded into the same 198i packaging/runtime harness job, never a separate dispatch. Existing installed refusal/full rollback and exact train compile gates still apply.

Runtime schema correction: corrupt_shader_fixture.fallback_role must equal sharp. It also needs log_association_verified and no_recursion_latch true. Its grain object requires shader_role grain, a separate shader_sha256 present in the full photon inventory but not either sharp hash, parse_ok/compile_ok/entry_preserved_after_shared_set true and an independently measured max_delta_from_bypass greater than zero. Sharp fallback max_delta_from_bypass and grain.max_delta_from_bypass are distinct measurements. Do not fill either from a combined effect delta.
