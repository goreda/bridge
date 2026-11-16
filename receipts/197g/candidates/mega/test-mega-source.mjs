import { encrypt } from 'megajs';
import { randomBytes, createCipheriv } from 'node:crypto';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { prepareMegaFile } from './MegaVerifiedSource.mjs';

const tmp = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'mega-owned-'));
let server;
try {
  const clear = fs.readFileSync(process.argv[2]);
  console.log('PHASE encrypt fixture');
  const encrypted = [], transform = encrypt(randomBytes(24));
  transform.on('data', chunk => encrypted.push(chunk));
  // MEGAJS encryption mutates input buffers. Keep the disk-read oracle immutable.
  await pipeline(Readable.from([Buffer.from(clear)]), transform);
  console.log('PHASE encryption complete');
  const ciphertext = Buffer.concat(encrypted), fullKey = transform.key;
  const aesKey = Buffer.alloc(16);
  for (let i = 0; i < 16; i++) aesKey[i] = fullKey[i] ^ fullKey[i + 16];
  const attributes = Buffer.from('MEGA' + JSON.stringify({ n: 'owned-fixture.wav' }));
  const padded = Buffer.alloc(Math.ceil(attributes.length / 16) * 16); attributes.copy(padded);
  const cipher = createCipheriv('aes-128-cbc', aesKey, Buffer.alloc(16)); cipher.setAutoPadding(false);
  const at = Buffer.concat([cipher.update(padded), cipher.final()]).toString('base64url');
  let corrupt = false, slow = false, unknown = false;
  server = http.createServer(async (req, res) => {
   try {
    if (slow) await new Promise(resolve => setTimeout(resolve, 1500));
    if (req.url.startsWith('/cs')) {
      const parts = [];for await (const c of req) parts.push(c);
      const command = JSON.parse(Buffer.concat(parts))[0];
      assert.equal(command.a, 'g');
      res.setHeader('Content-Type','application/json');
      res.end(JSON.stringify([unknown ? -9 : { s: clear.length, at, g: `http://127.0.0.1:${server.address().port}/cipher` }]));
    } else {
      assert.equal(req.url, `/cipher/0-${ciphertext.length - 1}`);
      const bytes = Buffer.from(ciphertext); if (corrupt) bytes[bytes.length - 1] ^= 1;
      res.end(bytes);
    }
   } catch (error) {
    // A cancelled client can abort while the async fixture is reading its
    // request. Do not turn that expected disconnect into an unhandled promise.
    if (error.code === 'ECONNRESET' && req.aborted) return;
    throw error;
   }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const testGateway = `http://127.0.0.1:${server.address().port}/`;
  // Ephemeral fixture link/key never printed, written to packet or sent remotely.
  const link = `https://mega.nz/file/OWNEDFIX#${fullKey.toString('base64url')}`;
  const opts = { link, testGateway, output: path.join(tmp,'good.wav') };
  console.log('PHASE resolve/decrypt');
  const result = await prepareMegaFile(opts);
  assert.equal(result.bytes, clear.length);assert.deepEqual(fs.readFileSync(opts.output),clear);
  console.log('PASS MEGAJS actual ciphertext download+decrypt+MAC into exact owned source bytes');
  const refuse = async (kind, changes) => {
    const output = path.join(tmp, 'bad-' + kind + '.wav');
    await assert.rejects(prepareMegaFile({ ...opts, output, ...changes }), error => error.kind === kind);
    assert.equal(fs.existsSync(output),false);console.log('PASS ' + kind + ' refusal and cache cleanup');
  };
  corrupt = true;await refuse('resolve_or_integrity',{});corrupt = false;
  const bad = Buffer.from(fullKey);bad[0] ^= 1;
  await refuse('resolve_or_integrity',{link:`https://mega.nz/file/OWNEDFIX#${bad.toString('base64url')}`});
  unknown = true;await refuse('resolve_or_integrity',{});unknown = false;
  await refuse('size_limit',{byteLimit:100});
  slow = true;await refuse('timeout',{timeoutMs:50});slow = false;
  const controller = new AbortController();controller.abort();await refuse('cancelled',{signal:controller.signal});
  console.log('m2-mega-crypto-source: all pass');
} finally {
  server?.closeAllConnections();await new Promise(resolve => server ? server.close(resolve) : resolve());
  await fs.promises.rm(tmp, { recursive: true, force: true });
}
