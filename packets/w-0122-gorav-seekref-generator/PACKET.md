generic ohal writer packet (block 89).

id: W | date: 2026-10-26 | to: any lab | subject: gorav line GP2: seeded seek-reference table generator (code)

Interface: `seekref <media> <seed> <count> <out.json>`. Deterministically derive <count> seek targets in
[0, duration] from the seed (documented LCG: x = (x*6364136223846793005 + 1442695040888963407) mod 2^64,
target = (x/2^64)*duration, 3-decimal rounding), run `ffmpeg -v info -ss T -copyts -i media -map 0:v:0
-frames:v 1 -vf showinfo -f null -` per target, parse the first shown frame pts, emit JSON
{"seed":..,"targets":[{"t":T,"landing_pts":P,"time_base":"1/12800"},...]} sorted by t.
Synthetic fixture: lab generates its own clip: ffmpeg -f lavfi -i testsrc2=size=160x90:rate=25 -t 5 -c:v mpeg4 -g 12 -bf 0 clip.mov.
Test: two runs on the same clip+seed produce BYTE-IDENTICAL JSON; targets reproducible from seed alone (no clock/PID entropy).
Est: <2h, Python stdlib + ffmpeg CLI.
- claimed by: OPEN.
