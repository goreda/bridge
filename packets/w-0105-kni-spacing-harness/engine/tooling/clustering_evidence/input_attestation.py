"""Role-bound byte attestation. No geometry evaluation or CLI is defined."""
from dataclasses import dataclass
from enum import Enum
import fcntl
import hashlib
import os
import stat
import time


class Status(str, Enum):
    VERIFIED = 'VERIFIED'
    NOT_EVALUATED = 'NOT_EVALUATED'
    UNVERIFIABLE = 'UNVERIFIABLE'


class AttestationError(ValueError):
    def __init__(self, code, message):
        self.code = code
        super().__init__(message)


def _sha(value):
    return isinstance(value, str) and len(value) == 64 and all(c in '0123456789abcdef' for c in value)


@dataclass(frozen=True)
class SourceRecord:
    kind: str
    identifier: str
    producer_tree_sha256: str


@dataclass(frozen=True)
class InputAttestation:
    role: str
    sha256: str
    physical_lines: int
    source: SourceRecord


@dataclass(frozen=True)
class Contract:
    """All bounds and allowed roles/source kinds must come from caller policy."""
    roles: tuple
    source_kinds: tuple
    max_file_bytes: int
    max_physical_lines: int
    max_identifier_chars: int
    read_chunk_bytes: int
    lock_timeout_ms: int
    lock_poll_ms: int

    def validate(self):
        for name in ('max_file_bytes', 'max_physical_lines', 'max_identifier_chars', 'read_chunk_bytes', 'lock_poll_ms'):
            if type(getattr(self, name)) is not int or getattr(self, name) <= 0:
                raise AttestationError('invalid_contract', name)
        if type(self.lock_timeout_ms) is not int or self.lock_timeout_ms < 0:
            raise AttestationError('invalid_contract', 'lock_timeout_ms')
        for values in (self.roles, self.source_kinds):
            if not isinstance(values, tuple) or not values or len(set(values)) != len(values):
                raise AttestationError('invalid_contract', 'unique policy values required')
            if any(not isinstance(v, str) or not v or not v.isascii() for v in values):
                raise AttestationError('invalid_contract', 'ASCII policy names required')


@dataclass(frozen=True)
class Result:
    status: Status
    reason: str
    byte_sha256: str = ''
    physical_lines: int = 0
    byte_count: int = 0
    logical_hash_status: Status = Status.NOT_EVALUATED
    snapshot_status: Status = Status.UNVERIFIABLE


def _signature(info):
    return (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def _validate(expected, role, source, contract):
    if not isinstance(expected, InputAttestation) or not isinstance(expected.source, SourceRecord) or not isinstance(source, SourceRecord):
        raise AttestationError('invalid_attestation', 'typed records required')
    if role not in contract.roles or expected.role != role:
        raise AttestationError('role_mismatch', 'input role does not match attestation')
    for item in (expected.source, source):
        if item.kind not in contract.source_kinds:
            raise AttestationError('source_kind', 'source kind is not in caller policy')
        if not isinstance(item.identifier, str) or not item.identifier or len(item.identifier) > contract.max_identifier_chars:
            raise AttestationError('invalid_source', 'source identifier bound')
        if any(0xD800 <= ord(c) <= 0xDFFF for c in item.identifier):
            raise AttestationError('invalid_source', 'invalid Unicode')
        if not _sha(item.producer_tree_sha256):
            raise AttestationError('invalid_source', 'producer tree SHA256 required')
    if expected.source != source:
        raise AttestationError('source_mismatch', 'source record mismatch')
    if not _sha(expected.sha256) or type(expected.physical_lines) is not int or not 0 <= expected.physical_lines <= contract.max_physical_lines:
        raise AttestationError('invalid_attestation', 'hash or line count')


def verify(path, expected, *, role, source, contract, consume_chunk, cooperative_lock=False):
    """Stream hash/count and pass the SAME bytes to a caller parser.

    consume_chunk is a staging-only sink. It must not publish parser results or
    cause side effects before VERIFIED is returned. Missing/unsupported logical
    schema is NOT_EVALUATED, not a fabricated logical hash. A cooperative lock
    certifies only this declared protocol, never arbitrary outside writers.
    """
    contract.validate()
    if expected is None:
        return Result(Status.NOT_EVALUATED, 'missing_input_attestation')
    if source is None:
        return Result(Status.NOT_EVALUATED, 'missing_source_record')
    _validate(expected, role, source, contract)
    if type(cooperative_lock) is not bool or not callable(consume_chunk):
        raise AttestationError('invalid_contract', 'lock policy and staging consumer required')
    flags = os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW
    fd = None
    try:
        try:
            fd = os.open(path, flags)
        except FileNotFoundError:
            return Result(Status.NOT_EVALUATED, 'missing_input_file')
        except OSError as error:
            raise AttestationError('input_open', str(error)) from error
        start = os.fstat(fd)
        if not stat.S_ISREG(start.st_mode):
            raise AttestationError('unsupported_input', 'regular file required')
        if start.st_size > contract.max_file_bytes:
            raise AttestationError('input_bound', 'file size exceeds policy')
        if cooperative_lock:
            from .receipt_storage import filesystem, StorageError
            try:filesystem(fd)
            except StorageError as error:raise AttestationError(error.code,str(error)) from error
            deadline = time.monotonic() + contract.lock_timeout_ms / 1000
            while True:
                try:
                    fcntl.flock(fd, fcntl.LOCK_SH | fcntl.LOCK_NB)
                    break
                except BlockingIOError as error:
                    if time.monotonic() >= deadline:
                        raise AttestationError('lock_timeout', 'cooperative input lock unavailable') from error
                    time.sleep(min(contract.lock_poll_ms / 1000, max(0, deadline - time.monotonic())))
                except OSError as error:
                    raise AttestationError('lock_failed', str(error)) from error
            # Do not include pre-lock activity as an in-lock mutation.
            start = os.fstat(fd)
        digest = hashlib.sha256()
        size = lines = 0
        last = None
        while True:
            chunk = os.read(fd, contract.read_chunk_bytes)
            if not chunk:
                break
            size += len(chunk)
            if size > contract.max_file_bytes:
                raise AttestationError('input_bound', 'stream exceeds byte bound')
            digest.update(chunk)
            lines += chunk.count(b'\n')
            last = chunk[-1]
            if lines > contract.max_physical_lines:
                raise AttestationError('input_bound', 'stream exceeds physical line bound')
            consume_chunk(chunk)
        if size and last != 10:
            lines += 1
        if lines > contract.max_physical_lines:
            raise AttestationError('input_bound', 'final line exceeds bound')
        end = os.fstat(fd)
        if _signature(start) != _signature(end) or size != end.st_size:
            raise AttestationError('input_mutated', 'file changed during read')
        actual = digest.hexdigest()
        if actual != expected.sha256:
            raise AttestationError('sha_mismatch', 'input bytes differ')
        if lines != expected.physical_lines:
            raise AttestationError('line_count_mismatch', 'physical line count differs')
        if not cooperative_lock:
            return Result(Status.UNVERIFIABLE, 'snapshot_writer_protocol_not_bound', actual, lines, size)
        return Result(Status.VERIFIED, 'bytes_verified_under_cooperative_lock_only', actual, lines, size,
                      snapshot_status=Status.VERIFIED)
    except OSError as error:
        raise AttestationError('input_io', str(error)) from error
    finally:
        if fd is not None:
            os.close(fd)
