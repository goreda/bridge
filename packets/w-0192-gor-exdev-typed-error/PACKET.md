generic ohal writer packet (block 89/91).

id: W-0192 | date: 2026-10-26 | to: any lab | subject: gor+photon line: typed EXDEV contract for cross-device rename

- base: the returned generic module at its public result URL (entry W-0131 in GROUP-INBOX). fetch it, keep its accepted tests untouched and green; this packet is an EXTENSION - new functionality/properties only, never a re-implementation or a re-run of the base's accepted tests.
- interface: document + implement the cross-device leg: when the backend reports EXDEV the adapter raises a TYPED CrossDeviceError (subclass of OSError) naming old/new paths; there is NO silent copy-and-delete fallback, ever.
- test: fake libc returning EXDEV -> typed raise with paths in the message; a probe attempting a real cross-fs rename is skipped unless an explicit env fixture provides two mount points.
- est: <1h.
- claimed by: OPEN.
