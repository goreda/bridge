#!/usr/bin/env python3
"""Generates deterministic malformed-container regression fixtures for
P-A1-R1 into Tests/BridgeDemuxTests/Fixtures/malformed/. Source bytes are
the package's own generated a1-* fixtures (public, synthetic)."""
import struct, os

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/.."
FIX = os.path.join(ROOT, "Tests/BridgeDemuxTests/Fixtures")
OUT = os.path.join(FIX, "malformed")

def u32(b,o): return struct.unpack(">I",b[o:o+4])[0]

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

def mk_bad_lace():
    """SimpleBlock with Xiph lace flag but no lace-count byte: block body is
    exactly track+timecode+flags (4 bytes), block is the last element of the
    file so an unguarded read steps past the buffer."""
    b=bytearray(open(os.path.join(FIX,"a1-audio.mkv"),'rb').read())
    seg_size_pos,seg_sl,seg_body,cpos,cil,csl,csize=find_cluster(b)
    csize_pos=cpos+cil
    cbody=csize_pos+csl
    o=cbody
    while o < cbody+csize:
        eid,il=read_id(b,o); sz,sl=read_size(b,o+il)
        if eid==0xA3: break
        o+=il+sl+sz
    blk=o; body=o+il+sl
    # flags byte at body+3; set lace=Xiph (bits 1-2 = 01)
    b[body+3]=(b[body+3] & ~0x06) | 0x02
    new=b[:body+4]  # cut payload AND everything after; block is last byte of file
    write_size(new, blk+il, sl, 4)
    write_size(new, csize_pos, csl, (body+4)-cbody)
    write_size(new, seg_size_pos, seg_sl, (body+4)-seg_body)
    open(os.path.join(OUT,"bad-lace-no-count.mkv"),'wb').write(bytes(new))

def _grow_cluster_element(b, field_id, new_payload, name, fix, seg_size_pos, seg_sl, seg_body, csize_pos, csl, csz, cbody):
    o=cbody
    while o<cbody+csz:
        eid,il=read_id(b,o); sz,sl=read_size(b,o+il)
        if eid==field_id:
            old_total=il+sl+sz
            nlen=len(new_payload)
            newel=bytearray(b[o:o+il])
            if nlen<=126: newel.append(0x80|nlen)
            else: newel+=bytes([0x40|(nlen>>8), nlen&0xff])
            newel+=new_payload
            delta=len(newel)-old_total
            new=b[:o]+newel+b[o+old_total:]
            write_size(new, csize_pos, csl, csz+delta)
            write_size(new, seg_size_pos, seg_sl, (cbody+csz-seg_body)+delta)
            open(os.path.join(OUT,name),'wb').write(bytes(new))
            return
        o+=il+sl+sz
    raise ValueError("element not found")

def mk_huge_ts():
    """Cluster Timecode = 0xFFFFFFFFFFFFFFFF (8 bytes): Int64 conversion overflow."""
    b=bytearray(open(os.path.join(FIX,"a1-audio.mkv"),'rb').read())
    seg_size_pos,seg_sl,seg_body,cpos,cil,csl,csz=find_cluster(b)
    _grow_cluster_element(b,0xE7,b"\xff"*8,"huge-cluster-timecode.mkv",None,seg_size_pos,seg_sl,seg_body,cpos+cil,csl,csz,cpos+cil+csl)

def mk_huge_scale():
    """TimestampScale = 0xFFFFFFFFFFFFFFFF (8 bytes): Int64 conversion overflow."""
    b=bytearray(open(os.path.join(FIX,"a1-audio.mkv"),'rb').read())
    o=0
    while o<len(b):
        eid,il=read_id(b,o); sz,sl=read_size(b,o+il)
        if eid==0x18538067:
            seg_size_pos=o+il; seg_sl=sl; seg_body=o+il+sl
            c=seg_body
            while c<seg_body+sz:
                eid2,il2=read_id(b,c); sz2,sl2=read_size(b,c+il2)
                if eid2==0x1549A966:
                    info_body=c+il2+sl2
                    q=info_body
                    while q<info_body+sz2:
                        eid3,il3=read_id(b,q); sz3,sl3=read_size(b,q+il3)
                        if eid3==0x2AD7B1:
                            old_total=il3+sl3+sz3
                            newel=bytearray(b[q:q+il3])
                            newel.append(0x88)  # 8-byte size
                            newel+=b"\xff"*8
                            delta=len(newel)-old_total
                            new=b[:q]+newel+b[q+old_total:]
                            write_size(new, c+il2, sl2, sz2+delta)
                            write_size(new, seg_size_pos, seg_sl, sz+delta)
                            open(os.path.join(OUT,"huge-timestamp-scale.mkv"),'wb').write(bytes(new))
                            return
                        q+=il3+sl3+sz3
                c+=il2+sl2+sz2
        o+=il+sl+sz
    raise ValueError("not found")

def find_box(b, path):
    start=0; end=len(b); off=None
    for want in path:
        o=start; found=None
        while o+8<=end:
            size=u32(b,o); typ=b[o+4:o+8]; hdr=8
            if size==1: size=struct.unpack(">Q",b[o+8:o+16])[0]; hdr=16
            if size==0: size=end-o
            if typ==want: found=(o+hdr,o+size); break
            o+=size
        if found is None: raise ValueError(f"{want} not found")
        off=found
        start,end=found
    return off

def mk_huge_box():
    """ftyp box with absurd largesize: size arithmetic must not overflow."""
    b=open(os.path.join(FIX,"a1-v24.mp4"),'rb').read()
    payload=b[8:36-8]  # drop 8 payload bytes to keep total length
    new=struct.pack(">I",1)+b"ftyp"+struct.pack(">Q",0x7FFFFFFFFFFFFFFF)+payload+b[36:]
    open(os.path.join(OUT,"huge-box-largesize.mp4"),'wb').write(new)

def mk_huge_stsz():
    """stsz sample_count = 0x3FFFFFFF with default_size=0: table bigger than file."""
    b=bytearray(open(os.path.join(FIX,"a1-v24.mp4"),'rb').read())
    s,e=find_box(b,[b"moov",b"trak",b"mdia",b"minf",b"stbl",b"stsz"])
    struct.pack_into(">I",b,s+8,0x3FFFFFFF)
    open(os.path.join(OUT,"huge-stsz-count.mp4"),'wb').write(bytes(b))

def mk_huge_ctts():
    """ctts first entry count = 0x40000000: run-length expansion must not explode."""
    b=bytearray(open(os.path.join(FIX,"a1-bframes.mp4"),'rb').read())
    s,e=find_box(b,[b"moov",b"trak",b"mdia",b"minf",b"stbl",b"ctts"])
    struct.pack_into(">I",b,s+8,0x40000000)
    open(os.path.join(OUT,"huge-ctts-count.mp4"),'wb').write(bytes(b))

def mk_huge_stts():
    """stts entry count = 0x7FFFFFFF: sum exceeds stsz; expansion must be bounded."""
    b=bytearray(open(os.path.join(FIX,"a1-v24.mp4"),'rb').read())
    s,e=find_box(b,[b"moov",b"trak",b"mdia",b"minf",b"stbl",b"stts"])
    struct.pack_into(">I",b,s+8,0x7FFFFFFF)
    open(os.path.join(OUT,"huge-stts-count.mp4"),'wb').write(bytes(b))

os.makedirs(OUT, exist_ok=True)
mk_bad_lace(); mk_huge_ts(); mk_huge_scale(); mk_huge_box(); mk_huge_stsz(); mk_huge_ctts(); mk_huge_stts()
print("malformed fixtures written to", OUT)
