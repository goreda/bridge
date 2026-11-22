# G7 supplied peer repair evidence, baseline unresolved

These three files came from Goreda peer: a drive/extract unified diff against its localv1 harness, a23:38 standalone regression receipt, and an older14:31 capacity JSON. No repository base commit or original full baseline is supplied. Do not claim patch applicability/current-source qualification until the actual matching baseline is recovered and the diff is applied/tested against it.

The23:38 receipt reports a standalone actual-fireRange-body regression and two runtime mutants plus Node syntax checks; it is NOT a live peer replay. The capacity JSON is older and reports maxConnected96, engine peakRSS674MB/final610MB, not a newly executed16-peer run. Neither is independently rerun by this relay. No repaired-current-product or G7closed verdict asserted.

Next step: obtain exact matching original drive.mjs/extract.mjs baseline and source/hash binding through coordinator, compare/apply safely, then inspect actual regression/test implementation and logs. Do not blindly rerun a swarm or duplicate the repair. Existing resource/safety limits remain; peer metrics do not authorize a new run or budget increase.
