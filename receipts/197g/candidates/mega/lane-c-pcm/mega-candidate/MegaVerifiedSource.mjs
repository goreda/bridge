// Engine source preparation backed by pinned MEGAJS, not an external player.
// Full verified-file subset. Range playback remains a separate owned row:
// partial MEGAJS downloads disable whole-file MAC verification by design.
import { API, File } from 'megajs';
import fs from 'node:fs';
import path from 'node:path';
import { Transform } from 'node:stream';
import { pipeline } from 'node:stream/promises';

export class MegaSourceError extends Error {
  constructor(kind) { super(kind); this.name = 'MegaSourceError'; this.kind = kind; }
}
export async function prepareMegaFile({ link, output, byteLimit = 64 * 1024 * 1024,
                                       timeoutMs = 25000, signal, testGateway } = {}) {
  if (typeof link !== 'string' || !/^https:\/\/mega\.(?:nz|co\.nz)\/file\/[A-Za-z0-9_-]+#[A-Za-z0-9_-]+$/.test(link)
      || !path.isAbsolute(output ?? '') || !Number.isSafeInteger(byteLimit) || byteLimit < 1
      || !Number.isFinite(timeoutMs) || timeoutMs < 1 || timeoutMs > 300000) throw new MegaSourceError('invalid_input');
  // Dependency injection is limited to local contract fixtures, not an arbitrary
  // proxy/redirect URL. Production leaves this unset and requires HTTPS.
  let allowedLocalOrigin;
  if (testGateway) {
    const gateway = new URL(testGateway);
    if (gateway.hostname !== '127.0.0.1' || gateway.protocol !== 'http:') throw new MegaSourceError('invalid_fixture_gateway');
    allowedLocalOrigin = gateway.origin;
  }
  const controller = new AbortController();
  const cancelled = () => controller.abort();
  signal?.addEventListener('abort', cancelled, { once: true });
  if (signal?.aborted) controller.abort();
  let timedOut = false, created = false, finished = false, body;
  const timer = setTimeout(() => { timedOut = true; controller.abort(); }, timeoutMs);
  const api = new API(false, {
    ...(testGateway ? { gateway: testGateway } : {}),
    fetch: async (url, options = {}) => {
      const target = new URL(url);
      if (target.protocol !== 'https:' && target.origin !== allowedLocalOrigin) throw new MegaSourceError('insecure_transport');
      return fetch(target, { ...options, redirect: 'error', signal: AbortSignal.any([controller.signal, ...(options.signal ? [options.signal] : [])]) });
    }
  });
  try {
    if (controller.signal.aborted) throw new MegaSourceError('cancelled');
    const file = File.fromURL(link, { api });
    await file.loadAttributes();
    if (!Number.isSafeInteger(file.size) || file.size < 1 || file.size > byteLimit) throw new MegaSourceError('size_limit');
    if (controller.signal.aborted) throw new MegaSourceError('cancelled');
    // Exclusive create avoids overwriting any existing file or following an
    // existing symlink. The caller owns removal after all decoder handles close.
    const handle = await fs.promises.open(output, 'wx', 0o600); created = true;
    const destination = handle.createWriteStream();
    let received = 0;
    const cap = new Transform({ transform(chunk, encoding, callback) {
      received += chunk.length;
      callback(received > byteLimit ? new MegaSourceError('size_limit') : null, chunk);
    } });
    // No start/end: full content must pass the library's MAC verification.
    body = file.download({ maxConnections: 1, forceHttps: true, handleRetries: (tries, error, callback) => callback(error) });
    await pipeline(body, cap, destination, { signal: controller.signal });
    if (received !== file.size) throw new MegaSourceError('size_mismatch');
    finished = true;
    return Object.freeze({ fileURL: new URL('file://' + output).href, bytes: received });
  } catch (error) {
    if (error instanceof MegaSourceError) throw error;
    if (timedOut) throw new MegaSourceError('timeout');
    if (controller.signal.aborted) throw new MegaSourceError('cancelled');
    // Library errors may contain URLs, link fragments, names or API details.
    // Return a typed neutral refusal rather than forwarding their text.
    throw new MegaSourceError('resolve_or_integrity');
  } finally {
    clearTimeout(timer); signal?.removeEventListener('abort', cancelled);
    controller.abort(); body?.destroy(); api.close();
    if (created && !finished) await fs.promises.rm(output, { force: true });
  }
}
