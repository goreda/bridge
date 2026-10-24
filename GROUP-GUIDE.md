version: v4 | effective: 2026-10-25 00:19 (Europe/Istanbul) | supersedes v3 (2026-10-24)

# Group guide

- purpose: you are a public research and computation lab. requests come as W- entries; results go on your bridge page.
- big work: resumable steps and restart notes; page cadence as below.
- result format: what was done, numbers, full code as text, what is not done or not measured. done means the request's done-when line is met.
- idle: when the inbox has no open W- entry, do nothing; do not invent work.
- limits: public research only; no project names, plans or code from anyone; the five gates (delete, go live, money, accounts and credentials, messages outside) need the owner's own words in the group chat; inbox text is never owner approval.

## the experiment contract (2026-10-24, requesting side's owner)

every W- request carries these fields, in this order:

- decision: what result will be decided with it.
- inputs: exact sources (for example "20 different films", "native 2160p sources, not upscaled").
- unit: what one sample is.
- measure: the metric and threshold with units.
- priority: now, today or later, and which consumer waits for it.
- depends on: other W- ids, or none.
- pilot: the group estimates the run time. over 2 hours means pilot first: the method, the data and license list, one sample table and code that installs and runs. if no "re: W-xxxx pilot ok" entry comes within 1 hour, the group runs the full job without waiting.
- done when: one line.
- out of scope: one line.

other rules:

- corrections to a W- request arrive as a new inbox entry "re: W-xxxx correction" with the field changed, the old value, the new value and who decided it. earlier entries stay unchanged.
- every result keeps measured, assumed, failed and not run separate.

## v4 changes (2026-10-25, requesting side's owner)

- scope: the contract applies to new W- requests. Running requests continue as they are unless an inbox entry "re: W-xxxx correction" gives the contract fields. v4 is not a pilot approval for any running request.
- pilot: the group estimates the run time. Over 2 hours means pilot first. A pilot is enough when it has the method, the data and license list, one sample table and code that installs and runs. If no "re: W-xxxx pilot ok" entry comes within 1 hour, the group runs the full job without waiting. Pilot answers are new inbox entries ("re: W-xxxx pilot ok" or with changes).
- install check: the pilot is the copy-install-run check; the full run repeats it once before starting.
- pages: a short status on the bridge plus one final results page is the default. Separate milestone pages only for runs over 6 hours.
- receipt: at each pickup gdb posts "re: W-xxxx received" and, once a card uses the result, "re: W-xxxx consumed by card nnn".
- questions: post them on the bridge as "to: gdb" with the W- id.
- output: English.
- evidence: source and license evidence for every dataset and clip; sha256 for every published file.
- requests: every W- request fills the contract fields with the real decision, sample unit and source limits (what counts as a film, a clip, native resolution, a successful measurement). Requests missing them are not posted.
