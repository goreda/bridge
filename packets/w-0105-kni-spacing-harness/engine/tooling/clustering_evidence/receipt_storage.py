"""Separate append-only receipt transport, not a geometry gate or CLI."""
import contextlib
import ctypes
import fcntl
import hashlib
import json
import os
from pathlib import Path
import struct
import stat
import sys
import time
from dataclasses import dataclass

FORMAT_VERSION = b'\x01'  # format-v1 convention: one version byte
ZERO_HASH = '0'*64
I64_MIN, I64_MAX = -(1<<63), (1<<63)-1
FILESYSTEMS = {0xEF53:'ext4', 0x58465342:'xfs', 0x9123683E:'btrfs', 0x01021994:'tmpfs'}

class StorageError(ValueError):
    def __init__(self, code, message):
        self.code=code
        super().__init__(message)


def canonical(value):
    def check(v):
        if type(v) is int:
            if not I64_MIN <= v <= I64_MAX:raise StorageError('integer_bound','i64 only')
        elif type(v) is str:
            if any(0xD800 <= ord(c) <= 0xDFFF for c in v):raise StorageError('invalid_unicode','surrogate')
        elif type(v) is list:
            for item in v:check(item)
        elif type(v) is dict:
            for k,item in v.items():
                if type(k) is not str or not k.isascii():raise StorageError('invalid_key','ASCII keys only')
                check(item)
        else:raise StorageError('invalid_type','int/string leaves only; bool/null/float forbidden')
    check(value)
    return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False,allow_nan=False).encode('utf-8')


def parse(raw):
    def pairs(items):
        out={}
        for k,v in items:
            if k in out:raise StorageError('duplicate_key',k)
            out[k]=v
        return out
    try:
        obj=json.loads(raw.decode('utf-8'),object_pairs_hook=pairs,
                       parse_float=lambda _: (_ for _ in ()).throw(StorageError('invalid_type','float')),
                       parse_constant=lambda _: (_ for _ in ()).throw(StorageError('invalid_type','constant')))
        if canonical(obj)!=raw:raise StorageError('noncanonical','payload is not canonical v1')
        return obj
    except (UnicodeError,ValueError,RecursionError) as error:
        if isinstance(error,StorageError):raise
        raise StorageError('invalid_json',str(error)) from error


def schema_bound(schema):
    """Conservative byte maximum for the supported bounded schema subset."""
    typ=schema.get('type')
    if 'enum' in schema and not schema['enum']:raise StorageError('unbounded_schema','empty enum')
    if typ=='string':
        n=schema.get('maxLength')
        if type(n) is not int or n<0 or type(schema.get('minLength')) is not int or not 0<=schema['minLength']<=n:raise StorageError('unbounded_schema','string min/maxLength required')
        return 2+6*n  # all allowed scalars have JSON encoding <=6 bytes
    if typ=='integer':
        a,b=schema.get('minimum'),schema.get('maximum')
        if type(a) is not int or type(b) is not int or not I64_MIN<=a<=b<=I64_MAX:raise StorageError('unbounded_schema','bounded i64 required')
        return max(len(str(a)),len(str(b)))
    if typ=='array':
        n=schema.get('maxItems')
        if type(n) is not int or n<0 or type(schema.get('minItems')) is not int or not 0<=schema['minItems']<=n:raise StorageError('unbounded_schema','array min/maxItems required')
        return 2+max(0,n-1)+n*schema_bound(schema['items'])
    if typ=='object':
        props=schema.get('properties',{})
        if schema.get('additionalProperties') is not False:raise StorageError('unbounded_schema','closed properties required')
        return 2+max(0,len(props)-1)+sum(len(canonical(k))+1+schema_bound(v) for k,v in props.items())
    raise StorageError('unsupported_schema','unsupported type')


def validate(value,schema):
    typ=schema.get('type')
    if 'enum' in schema and value not in schema['enum']:raise StorageError('schema','enum')
    if typ=='string':
        if type(value) is not str or len(value)>schema['maxLength'] or len(value)<schema.get('minLength',0):raise StorageError('schema','string bound')
    elif typ=='integer':
        if type(value) is not int or not schema['minimum']<=value<=schema['maximum']:raise StorageError('schema','integer bound')
    elif typ=='array':
        if type(value) is not list or not schema['minItems']<=len(value)<=schema['maxItems']:raise StorageError('schema','array bound')
        for item in value:validate(item,schema['items'])
    elif typ=='object':
        if type(value) is not dict or set(value)!=set(schema['properties']):raise StorageError('schema','exact keys required')
        for k,v in value.items():validate(v,schema['properties'][k])
    else:raise StorageError('unsupported_schema','unsupported type')
    canonical(value)


def filesystem(fd):
    # Linux statfs ABI: f_type is the first native long; overallocated buffer.
    if not sys.platform.startswith('linux'):raise StorageError('unsupported_filesystem','Linux statfs required')
    libc=ctypes.CDLL(None,use_errno=True);buf=ctypes.create_string_buffer(4096)
    if libc.fstatfs(fd,ctypes.byref(buf))!=0:raise StorageError('filesystem_probe','fstatfs failed')
    magic=ctypes.c_long.from_buffer(buf).value & 0xffffffff
    if magic not in FILESYSTEMS:raise StorageError('unsupported_filesystem',hex(magic))
    # ext magic is shared by ext2/3/4; cannot prove ext4 from magic alone.
    if magic==0xEF53:raise StorageError('unsupported_filesystem','ext family version unproven by statfs')
    return FILESYSTEMS[magic]


@dataclass(frozen=True)
class Anchor:
    last_sequence:int
    last_frame_hash:str


@dataclass(frozen=True)
class VerifiedLog:
    records:tuple
    anchor:Anchor
    tail_completeness:str


def _bindings(receipt):
    def sha(v):return type(v) is str and len(v)==64 and all(c in '0123456789abcdef' for c in v)
    for field in ('tree_sha256','gate_config_sha256'):
        if not sha(receipt.get(field)):raise StorageError('binding_hash',field)
    if type(receipt.get('input_sha256s')) is not list or any(not sha(v) for v in receipt['input_sha256s']):raise StorageError('binding_hash','inputs')
    variant=receipt.get('res_c2_col')
    if type(variant) is not dict or set(variant)!={'tag','value'}:raise StorageError('binding_variant','res_c2_col')
    if variant['tag']=='absent':
        if variant['value']!='':raise StorageError('binding_variant','absent has empty value')
    elif variant['tag']=='present':
        if not variant['value']:raise StorageError('binding_variant','present value required')
    else:raise StorageError('binding_variant','unknown tag')
    if receipt.get('logical_hash_status')!='NOT_EVALUATED':raise StorageError('logical_hash','not yet bound')
    if receipt.get('status')=='PASS':
        if receipt.get('co_gate_status')!='VERIFIED' or variant['tag']!='present' or not receipt['input_sha256s'] or not receipt.get('c2_source'):
            raise StorageError('unsupported_pass','missing verified co-gate evidence')
    if receipt.get('status') not in ('PASS','FAIL','NOT_EVALUATED','UNVERIFIABLE'):raise StorageError('status','unsupported')


def key(receipt):
    fields=('schema_version','tree_sha256','gate_id','gate_config_sha256','input_sha256s','c2_source','res_c2_col')
    try:return hashlib.sha256(canonical({k:receipt[k] for k in fields})).hexdigest()
    except KeyError as error:raise StorageError('missing_binding',str(error)) from error


def frame(sequence,payload):
    if type(sequence) is not int or not 1<=sequence<(1<<64):raise StorageError('sequence_bound','u64 sequence')
    if len(payload)>0xffffffff:raise StorageError('payload_bound','u32 length')
    header=struct.pack('>QI',sequence,len(payload))
    return FORMAT_VERSION+header+payload+hashlib.sha256(header+payload).digest()


def decode(raw,schema,anchor=None):
    bound=schema_bound(schema)
    if bound>0xffffffff:raise StorageError('payload_bound','schema maximum exceeds u32')
    offset=0;previous=ZERO_HASH;records=[];sequence=0;seen={}
    while offset<len(raw):
        if len(raw)-offset<13:raise StorageError('incomplete_or_corrupt_tail','partial header')
        version=raw[offset:offset+1]
        if version!=FORMAT_VERSION:raise StorageError('format_version','unsupported')
        seq,length=struct.unpack('>QI',raw[offset+1:offset+13])
        if seq!=sequence+1:raise StorageError('sequence','nonconsecutive')
        if length>bound:raise StorageError('payload_bound','invalid frame length')
        end=offset+13+length+32
        if end>len(raw):raise StorageError('incomplete_or_corrupt_tail','partial frame')
        payload=raw[offset+13:end-32]
        if hashlib.sha256(raw[offset+1:offset+13]+payload).digest()!=raw[end-32:end]:raise StorageError('corruption','checksum mismatch')
        obj=parse(payload);validate(obj,schema)
        _bindings(obj['receipt'])
        if obj['previous_frame_sha256']!=previous:raise StorageError('chain','previous frame mismatch')
        identity=key(obj['receipt']);content=hashlib.sha256(canonical(obj['receipt'])).hexdigest()
        if identity in seen:raise StorageError('duplicate_record','duplicate or conflicting committed key')
        seen[identity]=content
        previous=hashlib.sha256(raw[offset:end]).hexdigest();sequence=seq;records.append(obj['receipt']);offset=end
    actual=Anchor(sequence,previous)
    if anchor is not None and anchor!=actual:raise StorageError('anchor_mismatch','external anchor mismatch')
    return VerifiedLog(tuple(records),actual,'VERIFIED' if anchor is not None else 'UNVERIFIED')


@contextlib.contextmanager
def locked(path,timeout_ms,poll_ms):
    if type(timeout_ms) is not int or timeout_ms<0 or type(poll_ms) is not int or poll_ms<=0:raise StorageError('lock_policy','invalid bounds')
    path=Path(path)
    # No parent auto-create or replacement; parent durability belongs to caller.
    fd=None
    try:
        try:fd=os.open(path,os.O_RDWR|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
        except FileExistsError:fd=os.open(path,os.O_RDWR|os.O_NOFOLLOW|os.O_NONBLOCK)
        if not stat.S_ISREG(os.fstat(fd).st_mode):raise StorageError('unsupported_file','regular receipt file required')
        filesystem(fd)
        deadline=time.monotonic()+timeout_ms/1000
        while True:
            try:fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB);break
            except BlockingIOError as error:
                if time.monotonic()>=deadline:raise StorageError('lock_timeout','writer lock unavailable') from error
                time.sleep(min(poll_ms/1000,max(0,deadline-time.monotonic())))
        yield fd
    except OSError as error:raise StorageError('storage_io',str(error)) from error
    finally:
        if fd is not None:os.close(fd)


def append(path,receipt,schema,*,timeout_ms,poll_ms,anchor=None):
    bound=schema_bound(schema)
    if bound>0xffffffff:raise StorageError('payload_bound','schema maximum exceeds u32')
    # Validate new receipt before any file creation.
    _bindings(receipt)
    validate({'previous_frame_sha256':ZERO_HASH,'receipt':receipt},schema)
    with locked(path,timeout_ms,poll_ms) as fd:
        raw=b''
        while True:
            chunk=os.read(fd,65536)
            if not chunk:break
            raw+=chunk
        log=decode(raw,schema,anchor)
        for previous in log.records:
            if key(previous)==key(receipt):
                if canonical(previous)!=canonical(receipt):raise StorageError('idempotency_conflict','same key different receipt')
                return log
        obj={'previous_frame_sha256':log.anchor.last_frame_hash,'receipt':receipt}
        validate(obj,schema);payload=canonical(obj)
        if len(payload)>bound:raise StorageError('payload_bound','payload exceeds derived schema maximum')
        encoded=frame(log.anchor.last_sequence+1,payload)
        view=memoryview(encoded)
        while view:
            count=os.write(fd,view)
            if count<=0:raise StorageError('short_write','zero write')
            view=view[count:]
        os.fsync(fd)
        # Sync the parent even after an earlier failed create attempt.
        parent=os.open(str(Path(path).parent),os.O_RDONLY|os.O_DIRECTORY)
        try:os.fsync(parent)
        finally:os.close(parent)
        # New anchor is returned for external persistence, never silently trusted.
        result=decode(raw+encoded,schema)
        return result
