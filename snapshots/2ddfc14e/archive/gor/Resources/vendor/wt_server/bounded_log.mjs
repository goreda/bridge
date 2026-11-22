import fs from 'node:fs';

// One current plus one previous file. Synchronous append makes queued output
// unable to outrun the byte guard. Never follows a log/previous-file symlink.
export function appendBounded(path, text, cap = 10 * 1024 * 1024) {
  if (!Number.isSafeInteger(cap) || cap <= 0) throw new Error('invalid log byte cap');
  const prev = path + '.prev';
  for (const p of [path, prev]) {
    try { if (!fs.lstatSync(p).isFile() || fs.lstatSync(p).nlink !== 1) return false; }
    catch (e) { if (e.code !== 'ENOENT') return false; }
  }
  const bytes = Buffer.from(text);
  const row = bytes.length > cap ? bytes.subarray(bytes.length - cap) : bytes;
  let size = 0;
  try { size = fs.statSync(path).size; } catch (e) { if (e.code !== 'ENOENT') return false; }
  if (size + row.length > cap) {
    // Keep a bounded tail even when adopting an oversized legacy log.
    const fd = fs.openSync(path, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
    try {
      const tail = Buffer.alloc(Math.min(size, cap));
      fs.readSync(fd, tail, 0, tail.length, Math.max(0, size - tail.length));
      fs.writeFileSync(prev, tail, {flag: fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_TRUNC | fs.constants.O_NOFOLLOW, mode: 0o600});
    } finally { fs.closeSync(fd); }
    fs.truncateSync(path, 0);
  }
  const fd = fs.openSync(path, fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_APPEND | fs.constants.O_NOFOLLOW, 0o600);
  try { fs.writeSync(fd, row); } finally { fs.closeSync(fd); }
  return true;
}
