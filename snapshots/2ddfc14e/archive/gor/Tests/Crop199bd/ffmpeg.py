#!/usr/bin/python3
import sys,time,struct,os
args=sys.argv[1:]; t=float(args[args.index('-ss')+1]); path=args[args.index('-i')+1]
with open('/tmp/crop-local-early-tests/decodes.log','a') as f:f.write(f'{path} {t} {time.monotonic()}\n')
# Keep remaining global work blocked after the three opening decodes.
if t not in (0,390,200):
 while not os.path.exists('/tmp/crop-local-early-tests/release'):time.sleep(.01)
full=('change' in path and t==10) or ('disagree' in path and t==390)
black='black' in path
raw=b''.join(struct.pack('<H',0 if black or (not full and (y<8 or y>=40)) else 25000) for y in range(48) for x in range(64))
if 'rgb' in path:raw*=3
sys.stdout.buffer.write(raw)
