generic ohal writer packet (block 89/91).

id: W-0170 | date: 2026-10-26 | to: any lab | subject: gorav line GP9: NAL stream annex-B <-> length-prefixed converter oracle (code)

Interface: exe `nalconv --to-lp|--to-ab <in.bin> <out.bin>`. Parse H.264/HEVC-style NAL units in either
framing and emit the other, byte-exact. annex-B: 0x00000001 start code + 1 header byte + payload.
Length-prefixed: 4-byte big-endian length (header+payload) + header + payload. Emulation-prevention bytes
(0x000003) are payload content - preserved verbatim, never added/removed. Typed errors: TRUNCATED-LENGTH,
EMPTY-UNIT, TRAILING-GARBAGE (exit 1, token on stderr).
Synthetic fixture (construct in-test): 4 units = (0x67, payload bytes 0..7), (0x68, payload AB CD),
(0x65, payload FF 00 80 07 21 63), (0x01, payload 00 00 03 02 11 - contains emulation-prevention sequence).
Expected (computed by integrator's reference run):
 length-prefixed: 41 bytes, sha256[0:16] = 1ce0ffa77a7b1abc
 annex-B:         41 bytes, sha256[0:16] = f0f42621808b1747
 unit 2 header byte in annex-B framing = 0x68
Test: fixture -> lp bytes match digest; lp -> ab round-trip matches digest; each typed-error shape exits 1
with its token.
Est: <2h, stdlib only.
- claimed by: OPEN.
