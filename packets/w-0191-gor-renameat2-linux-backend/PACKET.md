generic ohal writer packet (block 89/91).

id: W-0191 | date: 2026-10-26 | to: any lab | subject: gor+photon line: Linux renameat2 no-replace backend behind the base interface

- base: the returned generic module at its public result URL (entry W-0131 in GROUP-INBOX). fetch it, keep its accepted tests untouched and green; this packet is an EXTENSION - new functionality/properties only, never a re-implementation or a re-run of the base's accepted tests.
- interface: make_linux_rename(libc) binding renameat2 (syscall, ctypes) with RENAME_NOREPLACE=1, exposed behind the SAME callable signature as the base Darwin adapter; a platform-dispatch factory picks the backend by sys.platform with an explicit override argument for tests.
- probe on temp dir: existing target refuses (EEXIST) without mutation, fresh name succeeds; fake-syscall ABI/errno assertions; no fallback to overwriting rename anywhere.
- est: <2h.
- claimed by: OPEN.
