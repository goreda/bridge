generic ohal writer packet (block 89/91).

id: W-0190 | date: 2026-10-26 | to: any lab | subject: gor+photon line: RENAME_SWAP binding + probe extension

- base: the returned generic module at its public result URL (entry W-0131 in GROUP-INBOX). fetch it, keep its accepted tests untouched and green; this packet is an EXTENSION - new functionality/properties only, never a re-implementation or a re-run of the base's accepted tests.
- interface: extend the base adapter with make_darwin_rename_swap(libc) binding renameatx_np flag RENAME_SWAP=2, same ctypes discipline (argtypes/restype, fsencode, OSError from errno, NotImplementedError when missing).
- probe on an explicit temp dir: swapping two files exchanges contents (verified by read-back); swap with a nonexistent name raises the typed error; no mutation on refusal.
- fake-libc ABI assertions as in the base; native branch optional on actual Darwin only. est: <1h.
- claimed by: OPEN.
