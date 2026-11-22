#!/usr/bin/env python3
"""P-A1-R2 fixtures: triggers for the two defects alleged in packet P-A4 E2.
Derived from the package's own generated a1-* media (public, synthetic)."""
import struct, os

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/.."
FIX = os.path.join(ROOT, "Tests/BridgeDemuxTests/Fixtures")
OUT = os.path.join(FIX, "malformed")

def read_id(b,o):
    l=1; m=0x80
    while l<=4 and not (b[o]&m): l+=1; m>>=1
    v=0
    for i in range(l): v=(v<<8)|b[o+i]
    return v,l
def read_size(b,o):
    l=1; m=0x80
    while l<=8 and not (b[o]&m): l+=1; m>>=1
    v=b[o]&(m-1)
    for i in range(1,l): v=(v<<8)|b[o+i]
    return v,l
def write_size(buf,o,l,v):
    for i in range(l-1,-1,-1):
        buf[o+i]=v&0xff; v>>=8
    buf[o]|=0x80>>(l-1)
def vint_size(v):
    if v <= 126: return bytes([0x80|v])
    return bytes([0x40|(v>>8), v&0xff])

def find_cluster(b):
    o=0
    while o<len(b):
        eid,il=read_id(b,o); sz,sl=read_size(b,o+il)
        if eid==0x18538067:
            seg_size_pos=o+il; seg_sl=sl; seg_body=o+il+sl; seg_end=seg_body+sz
            c=seg_body
            while c<seg_end:
                eid2,il2=read_id(b,c); sz2,sl2=read_size(b,c+il2)
                if eid2==0x1F43B675:
                    return seg_size_pos,seg_sl,seg_body,c,il2,sl2,sz2
                c+=il2+sl2+sz2
        o+=il+sl+sz
    raise ValueError("no cluster")

def mk_lace_overflow():
    """BlockGroup with BlockDuration = 0xFFFFFFFFFFFFFFFF wrapping a
    fixed-laced block (2 laces): bl * (n+1) overflows Int64; R1 drops the
    overflow flag via .partialValue and emits garbage (non-conserving)
    per-lace durations instead of a typed error."""
    b=bytearray(open(os.path.join(FIX,"a1-audio.mkv"),'rb').read())
    seg_size_pos,seg_sl,seg_body,cpos,cil,csl,csize=find_cluster(b)
    csize_pos=cpos+cil
    cbody=csize_pos+csl
    # first SimpleBlock in the cluster
    o=cbody
    while o < cbody+csize:
        eid,il=read_id(b,o); sz,sl=read_size(b,o+il)
        if eid==0xA3: break
        o+=il+sl+sz
    blk=o; body=o+il+sl; payload=b[body+4:body+sz]
    # block header: track vint + 2 timecode bytes + flags (at body+3)
    hdr=bytearray(b[body:body+4])
    hdr[3] |= 0x04  # lace = fixed (bits 1-2 = 10)
    pay=bytearray(payload)
    if len(pay)%2: pay=pay[:-1]  # fixed lacing needs divisibility
    newblk=bytes(hdr)+b"\x01"+bytes(pay)  # count byte 1 -> 2 laces
    group=bytearray()
    group+=b"\x9B"+vint_size(8)+b"\xff"*8        # BlockDuration = UInt64.max
    group+=b"\xA1"+vint_size(len(newblk))+newblk  # Block
    newel=bytearray(b"\xA0")+vint_size(len(group))+group
    old_total=il+sl+sz
    delta=len(newel)-old_total
    new=b[:blk]+newel+b[blk+old_total:]
    write_size(new, csize_pos, csl, csize+delta)
    write_size(new, seg_size_pos, seg_sl, (cbody+csize-seg_body)+delta)
    open(os.path.join(OUT,"lace-duration-overflow.mkv"),'wb').write(bytes(new))

def box(t, payload):
    return struct.pack(">I", 8+len(payload))+t+payload

def fullbox(t, version, flags, payload):
    return box(t, bytes([version])+flags.to_bytes(3,'big')+payload)

def mk_rescale_overflow():
    """Progressive MP4 whose last sample lands at dts = 9223372036355 with
    timescale 1e9: dts*1_000_000 fits Int64, but the round-to-nearest
    addition r + timescale/2 overflows -> R1 traps (exit 132), R2 throws a
    typed error. Minimal synthetic file, no captured content."""
    nsamp=2149
    d1=4294967295   # 2147 samples at max u32 delta
    d2=2077253990   # fine-tuned so sample 2148's dts = 2147*d1 + d2 = 9223372036355
    assert 2147*d1+d2 == 9223372036355
    ts=1_000_000_000
    stsd=fullbox(b"stsd",0,0, struct.pack(">I",1)+struct.pack(">I",28)+b"avc1"+b"\x00"*20)
    # entry1: 2147 samples at delta d1; entry2: 1 sample at delta d2; entry3:
    # 1 sample (its delta is irrelevant). Sample 2148 decodes at
    # dts = 2147*d1 + d2 = 9223372036355.
    stts=fullbox(b"stts",0,0, struct.pack(">I",3)+struct.pack(">II",2147,d1)+struct.pack(">II",1,d2)+struct.pack(">II",1,512))
    stsc=fullbox(b"stsc",0,0, struct.pack(">IIII",1,1,nsamp,1))
    stsz=fullbox(b"stsz",0,0, struct.pack(">II",1,nsamp))
    mdat=box(b"mdat", b"\x00"*nsamp)
    # stco patched after layout known
    stco=fullbox(b"stco",0,0, struct.pack(">II",1,0))
    stbl=box(b"stbl", stsd+stts+stsc+stsz+stco)
    minf=box(b"minf", stbl)
    hdlr=fullbox(b"hdlr",0,0, b"\x00"*8+b"vide"+b"\x00"*12+b"Video\x00")
    mdhd=fullbox(b"mdhd",0,0, struct.pack(">IIIIH",0,0,ts,0,0)+b"\x00\x00")
    mdia=box(b"mdia", mdhd+hdlr+minf)
    tkhd=fullbox(b"tkhd",0,3, struct.pack(">IIIII",0,0,1,0,0)+b"\x00"*52)
    trak=box(b"trak", tkhd+mdia)
    moov=box(b"moov", trak)
    ftyp=box(b"ftyp", b"isom\x00\x00\x02\x00isom")
    mdat_off=len(ftyp)+len(moov)+8
    stco=fullbox(b"stco",0,0, struct.pack(">II",1,mdat_off))
    stbl=box(b"stbl", stsd+stts+stsc+stsz+stco)
    minf=box(b"minf", stbl)
    mdia=box(b"mdia", mdhd+hdlr+minf)
    trak=box(b"trak", tkhd+mdia)
    moov=box(b"moov", trak)
    open(os.path.join(OUT,"rescale-rounding-overflow.mp4"),'wb').write(ftyp+moov+mdat)

os.makedirs(OUT, exist_ok=True)
mk_lace_overflow(); mk_rescale_overflow()
print("r2 fixtures written")
