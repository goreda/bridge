// Diagnostic-only seams. No selection, admission, retries, bytes or response status changes.
export function makeLagSampler({pid, platform, execFile, emit, directory = "/tmp", now = Date.now}) {
  let running = false, lastAt = -Infinity, count = 0;
  return lagMs => {
    if (platform !== 'darwin' || !Number.isFinite(lagMs) || lagMs <= 1000 || running || count >= 4 || now() - lastAt < 60000) return;
    running = true; lastAt = now(); const sequence = ++count;
    const file = `${directory}/gor-wt-lag-${pid}-${sequence}.txt`;
    emit({kind:'node-sample-start', pid, sequence, lagMs, observedAtMs:lastAt, timing:'post-lag-not-retrospective'});
    const done = error => {
      running = false;
      emit({kind:'node-sample-end', pid, sequence, ok:!error, timing:'post-lag-not-retrospective'});
    };
    try { execFile('/usr/bin/sample', [String(pid), '1', '1', '-file', file], {timeout:4000, maxBuffer:16384}, done); }
    catch (error) { done(error); }
  };
}

export function makeHTTPTracer({emit, now = Date.now, cap = 4096}) {
  let sequence = 0;
  return (req, res) => {
    if (!['GET','HEAD'].includes(req.method) || sequence >= cap) return;
    const id = ++sequence, startedAtMs = now();
    const range = /^bytes=(\d+)-(\d*)$/.exec(req.headers.range || '');
    const rangeStart = range ? Number(range[1]) : null;
    const rangeEnd = range && range[2] ? Number(range[2]) : null;
    let firstWriteMs = null, lastAt = null, maxWriteGapMs = 0, bytes = 0, ended = false;
    const recordChunk = chunk => {
      if (typeof chunk !== 'string' && !ArrayBuffer.isView(chunk)) return;
      const size = typeof chunk === 'string' ? Buffer.byteLength(chunk) : chunk.byteLength;
      if (!size) return;
      const at = now();
      if (firstWriteMs === null) {
        firstWriteMs = at - startedAtMs;
        emit({kind:'http-first-write', id, startedAtMs, rangeStart, rangeEnd, status:res.statusCode, firstWriteMs});
      }
      if (lastAt !== null) maxWriteGapMs = Math.max(maxWriteGapMs, at - lastAt);
      lastAt = at; bytes += size;
    };
    for (const name of ['write','end']) {
      const original = res[name];
      if (typeof original !== 'function') continue;
      res[name] = function(chunk, ...args) {
        recordChunk(chunk); return original.call(this, chunk, ...args);
      };
    }
    const finish = completed => {
      if (ended) return; ended = true;
      emit({kind:'http-latency', id, startedAtMs, rangeStart, rangeEnd, status:res.statusCode,
        firstWriteMs, totalMs:now()-startedAtMs, maxWriteGapMs, bytes, completed});
    };
    res.once('finish', () => finish(true));
    res.once('close', () => finish(false));
  };
}
