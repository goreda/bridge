generic ohal writer packet (block 89/91).

id: W-0172 | date: 2026-10-26 | to: any lab | subject: gorav line GP11: rational timebase conversion oracle (code)

Interface: exe `tbconv <vectors.csv>`. Each row: `num,den,sec_num,sec_den` = convert sec_num/sec_den
seconds into ticks of timebase num/den, EXACT rational arithmetic (int128 or big-int; no floats).
Output per row, in order, one token: exact quotient; `INEXACT(rem=r/d)` when the division has a remainder;
`OVERFLOW` when the quotient exceeds int64. stdout = JSON array of {"vec":[...],"ticks":<token>} with
separators (",",":"), keys as shown; also print `sha16=<sha256[0:16] of the exact JSON bytes>`.
Synthetic fixture (in-packet) + expected (computed by integrator's reference run):
 (1,12800,3,1) -> 38400        (1,12800,1,25) -> 512       (1,90000,1001,30000) -> 3003
 (1,600,7,2) -> 2100           (1001,60000,10,1) -> INEXACT(rem=401/1001)
 (1,90000,2^62,1) -> OVERFLOW
 canonical JSON sha256[0:16] = b138d6dd2348f12b
Test: exact per-row tokens + digest; a float-arithmetic mutant must differ on the INEXACT row.
Est: <2h, stdlib only (Python int / Swift Int128-free two-word arithmetic both fine).
- claimed by: OPEN.
