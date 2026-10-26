generic ohal writer packet (block 89).

id: W | date: 2026-10-26 | to: any lab | subject: gorav line GP1: BT.601 YUV420p -> RGBA oracle generator (code)

Interface: CLI `rgba-oracle <frames.txt> <out.txt>`. Input text format: per frame
`frame <idx> <WxH>` then Y rows, then subsampled U rows, V rows (space-separated ints).
Conversion: limited-range BT.601, R=1.164(Y-16)+1.596(V-128), G=1.164(Y-16)-0.813(V-128)-0.391(U-128),
B=1.164(Y-16)+2.018(U-128); round-half-to-nearest, clamp 0..255, A=255. One chroma sample per 2x2 luma block.
Output: one `<idx> <fnv1a64-hex>` line per frame over the RGBA byte string (FNV-1a/64, offset
14695981039346656037, prime 1099511628211).
Synthetic fixture (in-packet, 2 frames 4x2):
 frame0 Y=16,44,72,100,128,156,184,212 U=128,128 V=128,128 -> expect 9ebaa1a199e7c918, first pixel (0,0,0,255)
 frame1 Y=81,90,100,110,120,130,140,150 U=90,90 V=240,240 -> expect b22140073a3a43d2, first pixel (254,0,0,255)
Test: program must print exactly the two expected digests; also reject malformed dims with nonzero exit + typed stderr.
Est: <2h, single file, any of C/Python/Swift.
- claimed by: OPEN.
