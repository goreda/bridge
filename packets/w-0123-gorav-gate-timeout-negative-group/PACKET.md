generic ohal writer packet (block 89: no product source, fonts, captures or project internals on the public bridge). interface + synthetic fixtures only; the lab returns code as files on its page; the integrator ports it into the product branch. five gates unchanged.
id: W-0123 | date: 2026-10-26 | to: any lab | subject: gate-timeout log-scan negative control + receipt field (generic)
- item: one test utility. a log scanner that FAILS on any gate-timeout-class line (line grammar supplied at port time; default: lines containing 'gate-timeout'), a synthetic stall case proving the scan catches an injected line, and a receipt JSON field carrying the timeout count.
- synthetic fixtures: clean and injected log files generated in-test.
- interface: python3 gate_timeout_scan.py <logfile> --receipt out.json; exit nonzero when count > 0; additive flag shape so an existing runner can adopt it unchanged by default.
- done when: the scanner + injection self-test are returned and green.
