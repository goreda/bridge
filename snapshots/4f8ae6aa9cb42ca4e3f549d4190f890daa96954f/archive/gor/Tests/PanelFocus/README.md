# Shared panel focus regression checks

The traversal fixture compiles the production generic resolver. `check.py` extracts the actual production restore/resign methods unchanged except the AppKit override boundary and executes them against small view/editor stubs. It checks nested mono/stereo lookup, hidden/disabled fields, existing field editor and non-text control preservation, inactive no-op, saved selection and clamping. It is not native AppKit proof.

Native window switching, first activating click, IME composition, Escape/Return, and right-eye click geometry remain UNRUN. No owner rerun kit is required. The first right-eye click intentionally activates AND acts on the mirrored control, matching the existing forwarder.

Magnet keeps `onEscape -> dismissSearch`, `onReturn -> commitSearch(field)`, its `cancelOperation` and keyDown callbacks, plus its text delegate `cancelOperation` and `insertNewline` handlers. Each handled route returns without calling the superclass or forwarding the same Escape. Browser monitors route a native input-panel Escape only through that panel's cancelOperation, never to the player or browser close handler; marked text is left to the editor. Passive About text-only mirror stays noninteractive.

Code hazards corrected: one-level field lookup under stereo wrapping; repeated delayed activation; app-wide Escape monitors acting on unrelated window events. These are source-grounded hazards. The exact causality of the owner's observed native window-return failure was not measured here.
