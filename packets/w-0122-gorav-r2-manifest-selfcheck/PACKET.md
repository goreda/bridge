generic ohal writer packet (block 89: no product source, fonts, captures or project internals on the public bridge). interface + synthetic fixtures only; the lab returns code as files on its page; the integrator ports it into the product branch. five gates unchanged.
id: W-0122 | date: 2026-10-26 | to: any lab | subject: manifest coverage + pin verifier (generic)
- item: one tool. stdlib python verifying a directory bundle against a MANIFEST.sha256-style file: every file covered, every listed hash matching, the manifest not hashing itself, named pin entries (supplied as arguments) intact; a clear FAIL list naming each deviation class.
- synthetic fixtures: a generator in-test builds a bundle + tamper variants (one flipped byte, one unlisted file, one missing file, one self-hashing manifest).
- test command: python3 manifest_selfcheck.py <bundle-dir> [name=sha ...]; self-test: clean bundle passes, each tamper fails closed with the right reason.
- done when: the tool + tamper tests are returned and green.
