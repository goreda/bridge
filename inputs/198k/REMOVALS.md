# Owner-approved delivered feature removals

Only the four internal model transports below are approved for removal as part of replacing the old G1-G4 paths with the v4 Lua/Swift twin. Source: original owner-pasted arch-198d, phonemsg-01M7JZ4W1HWK0RZXFD8Z44C3BB, November 16 at 23:00:32 +03. It orders V1/V2 replacement of the G1-G4 code paths; Main applied the exact transport mapping at 23:50 and corrected its spelling at 23:51. This is not approval to remove an owner-facing control.

| Kind | Exact internal name | Owner instruction id |
| --- | --- | --- |
| script_messages | photon-grain-set-strength-hint | phonemsg-01M7JZ4W1HWK0RZXFD8Z44C3BB |
| script_messages | photon-grain-set-strength-mult | phonemsg-01M7JZ4W1HWK0RZXFD8Z44C3BB |
| script_messages | photon-grain-proxy-strength | phonemsg-01M7JZ4W1HWK0RZXFD8Z44C3BB |
| script_messages | photon-grain-set-size-hint | phonemsg-01M7JZ4W1HWK0RZXFD8Z44C3BB |

photon-grain-strength-resume stays. photon-grain-set-strength-proxy is not a real registered name and is not an approved removal. Every owner-facing menu, binding and manual message stays. No other removal rides on this order. No stub or disable is permitted to pass a gate. Candidate changes still need all other gates and actual v4 behavior acceptance; these records do not authorize a delivery or engine switch.

## Separate V1 script-option patch removals

Original owner arch-198d V1, phonemsg-01M7JZ4W1HWK0RZXFD8Z44C3BB, explicitly says "Remove the 1.2 reference, the 0.75..2.5 r clamp, the sdclass hold and the 480p floor/ceiling patches." The following exact obsolete patch options may be removed by that replacement. This set is separate from the four internal transports above.

| Kind | Exact internal name | Owner instruction id |
| --- | --- | --- |
| script_options | photon-grain_floor_480p | phonemsg-01M7JZ4W1HWK0RZXFD8Z44C3BB |
| script_options | photon-grain_ceiling_480p | phonemsg-01M7JZ4W1HWK0RZXFD8Z44C3BB |

No manual, menu, key, binding, shader or file removal is approved by this set. Do not stub or disable a feature to pass the gate.

## Same-candidate replacement condition (arch-198h)

Owner execution check phonemsg-01M7K2FRXFBQ11PBBA6XE0KDBG, November 16 at 23:58:55, requires every candidate touching the G1-G4 paths to carry the v4 twin V1-V7. The named allowances above apply only when that replacement is present in the same exact candidate. The runtime evidence must bind replacement results, Lua/Swift byte equality, V7 invariants and manual recall sequence to the candidate executable SHA256. Without it, the checker applies no removal allowance. Nothing is stubbed or disabled to make a gate pass.
