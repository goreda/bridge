# Menu static IPC command contract

Run `bash gor/Tests/Harness/MenuCommands/run.sh`. Python 3 only, current MenuActions.swift required. Extracts literal cmd raw-string JSON directly from current source and validates command object/array shape; checks 13 key action mappings including reload arity, seeks and speeds. Three source mutations fail. Dynamic interpolation is explicitly excluded rather than treated as valid JSON. No snapshot fallback or model substitute for extracted literals.

JSON validity is not installed mpv command/version acceptance or UI menu wiring proof. Dynamic cmd strings, aspect/VR/profile/media/companion behavior and native action dispatch are outside this cell. Reload trailing-yes issue is historical, current one-argument mapping is a regression control. No production edits, Swift/menu/mpv/UI or network actions. PASS is static command contract evidence only.
