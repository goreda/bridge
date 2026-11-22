#!/usr/bin/env node
// bridge_uindex.mjs - local browser bridge: renders uindex search.php through
// real Chrome (persistent gor-owned profile, AutomationControlled off) via raw
// CDP (no npm deps), waits out the Cloudflare auto-challenge, and prints the
// results table HTML on stdout for parseUindex. Exit 0 = rows rendered; else walled.
// Usage: node bridge_uindex.mjs <chrome-path> <query> [--selftest]
import {spawn} from 'node:child_process';
import {connect} from 'node:net';
import {createHash, randomBytes} from 'node:crypto';
import http from 'node:http';

const [shellPath, query, flag] = process.argv.slice(2);
if (!shellPath || !query) { console.error('usage: node bridge_uindex.mjs <shell> <query> [--selftest]'); process.exit(64); }
const url = process.env.BRIDGE_URL || 'https://uindex.org/search.php?search=' + encodeURIComponent(query).replace(/%20/g,'+') + '&c=0';
const TIMEOUT = Number(process.env.BRIDGE_TIMEOUT) || 90000;

const wsHandshake = (port, path) => new Promise((res, rej) => {
  const key = randomBytes(16).toString('base64');
  const sock = connect(port, '127.0.0.1', () => {
    sock.write(`GET ${path} HTTP/1.1\r\nHost: 127.0.0.1:${port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: ${key}\r\nSec-WebSocket-Version: 13\r\n\r\n`);
  });
  let head = Buffer.alloc(0), up = false;
  sock.on('data', d => {
    if (up) return;
    head = Buffer.concat([head, d]);
    const i = head.indexOf('\r\n\r\n');
    if (i === -1) return;
    if (!head.subarray(0, i).toString().includes('101')) return rej(new Error('ws upgrade refused'));
    up = true; res({sock, rest: head.subarray(i + 4)});
  });
  sock.on('error', rej);
});

const encodeFrame = (payload) => {
  const data = Buffer.from(payload);
  const mask = randomBytes(4);
  const len = data.length;
  const head = len < 126 ? Buffer.from([0x81, 0x80 | len])
    : len < 65536 ? Buffer.from([0x81, 0x80 | 126, len >> 8, len & 255])
    : (() => { const b = Buffer.alloc(10); b[0] = 0x81; b[1] = 0x80 | 127; b.writeBigUInt64BE(BigInt(len), 2); return b; })();
  const masked = Buffer.from(data);
  for (let i = 0; i < masked.length; i++) masked[i] ^= mask[i & 3];
  return Buffer.concat([head, mask, masked]);
};

const frameParser = () => {
  let buf = Buffer.alloc(0), frags = [];
  return {
    push(chunk, onMsg) {
      buf = Buffer.concat([buf, chunk]);
      for (;;) {
        if (buf.length < 2) return;
        const fin = buf[0] & 0x80, op = buf[0] & 0x0f;
        let len = buf[1] & 0x7f, off = 2;
        if (len === 126) { if (buf.length < 4) return; len = buf.readUInt16BE(2); off = 4; }
        else if (len === 127) { if (buf.length < 10) return; len = Number(buf.readBigUInt64BE(2)); off = 10; }
        if (buf.length < off + len) return;
        const payload = buf.subarray(off, off + len);
        buf = buf.subarray(off + len);
        if (op === 9 || op === 10) continue;           // ping/pong (server pings are rare here)
        frags.push(payload);
        if (fin) { onMsg(Buffer.concat(frags).toString()); frags = []; }
      }
    }
  };
};

const getJSON = (port, path) => new Promise((res, rej) => {
  http.get({host: '127.0.0.1', port, path}, r => {
    let b = ''; r.on('data', d => b += d); r.on('end', () => { try { res(JSON.parse(b)); } catch (e) { rej(e); } });
  }).on('error', rej);
});

const fail = (code, msg) => { console.error(msg); try { browser.kill('SIGKILL'); } catch {} process.exit(code); };

const launchArgs = ['--remote-debugging-port=0', '--no-first-run', '--disable-gpu',
  '--disable-dev-shm-usage', '--hide-scrollbars', '--mute-audio',
  '--disable-blink-features=AutomationControlled', '--window-size=1280,800', '--window-position=3000,3000'];
launchArgs.push('--user-data-dir=' + (process.env.BRIDGE_USER_DATA_DIR || (process.env.HOME + '/.gor/browser-profile')));
launchArgs.push('about:blank');
const browser = spawn(shellPath, launchArgs, {stdio: ['ignore', 'pipe', 'pipe']});
browser.on('error', e => fail(66, 'cannot launch browser: ' + e.message));

const wsLine = await new Promise((res, rej) => {
  let err = '';
  browser.stderr.on('data', d => {
    err += d;
    const m = err.match(/DevTools listening on (ws:\/\/\S+)/);
    if (m) res(m[1]);
  });
  browser.on('exit', () => rej(new Error('browser exited before DevTools came up')));
  setTimeout(() => rej(new Error('DevTools endpoint never appeared')), 20000);
}).catch(e => fail(66, e.message));

const wsURL = new URL(wsLine);
const port = Number(wsURL.port);
const {sock, rest} = await wsHandshake(port, wsURL.pathname).catch(e => fail(66, 'ws connect: ' + e.message));

let msgId = 0, sessionId = null;
const pendingReplies = new Map();
const send = (method, params = {}, sid) => new Promise((res, rej) => {
  const id = ++msgId;
  pendingReplies.set(id, {res, rej});
  const m = {id, method, params};
  if (sid) m.sessionId = sid;
  sock.write(encodeFrame(JSON.stringify(m)));
});
const parser = frameParser();
const onMessage = (text) => {
  let m; try { m = JSON.parse(text); } catch { return; }
  if (m.id && pendingReplies.has(m.id)) {
    const p = pendingReplies.get(m.id); pendingReplies.delete(m.id);
    m.error ? p.rej(new Error(m.error.message)) : p.res(m.result);
  }
};
sock.on('data', d => parser.push(d, onMessage));
if (rest.length) parser.push(rest, onMessage);
sock.on('error', e => fail(66, 'ws error: ' + e.message));

const {targetId} = await send('Target.createTarget', {url: 'about:blank'});
({sessionId} = await send('Target.attachToTarget', {targetId, flatten: true}));
await send('Page.enable', {}, sessionId);
await send('Runtime.enable', {}, sessionId);
await send('Network.enable', {}, sessionId).catch(()=>{});
await send('Page.addScriptToEvaluateOnNewDocument', {source:
  "Object.defineProperty(navigator,'webdriver',{get:()=>undefined});"}, sessionId).catch(()=>{});
await send('Page.navigate', {url}, sessionId);

const evalJS = async (expr) => (await send('Runtime.evaluate',
  {expression: expr, returnByValue: true}, sessionId)).result?.value;

const clearance = async () => {
  try {
    const {cookies} = await send('Network.getAllCookies', {}, sessionId);
    return (cookies||[]).some(c => c.name === 'cf_clearance' && /uindex\.org$/.test(c.domain||''));
  } catch { return false; }
};
const challengeType = async () => {
  const t = await evalJS("(()=>{const d=document;const html=(d.title||'')+' '+(d.body?d.body.innerText.slice(0,500):'');if(!/just a moment|verify you are human|checking your browser/i.test(html))return 'none';return d.querySelector('iframe[src*=challenges]')?'interactive':'non-interactive'})()").catch(() => 'unknown');
  return t || 'unknown';
};
const SELECTOR = process.env.BRIDGE_SELECTOR || 'td.sr-col-name';
const GENERIC = process.env.BRIDGE_GENERIC === '1';
const countRows = async () => {
  if (GENERIC) return (await challengeType()) === 'none' ? 1 : 0;
  return await evalJS(`document.querySelectorAll('${SELECTOR}').length`).catch(() => 0) || 0;
};
const t0 = Date.now();
let rows = 0, hinted = false, retried = false, lastType = 'unknown';
while (Date.now() - t0 < TIMEOUT) {
  await new Promise(r => setTimeout(r, 3000));
  rows = await countRows();
  if (rows > 0) break;
  lastType = await challengeType();
  if (lastType !== 'none' && !hinted) {
    hinted = true;
    console.error(`challenge on screen (type: ${lastType}), waiting for automatic pass...`);
  }
  // clearance issued but page not reloaded? re-navigate with the new cookie
  if (await clearance()) {
    console.error('cf_clearance issued, re-navigating with clearance...');
    await send('Page.navigate', {url}, sessionId).catch(()=>{});
    await new Promise(r => setTimeout(r, 5000));
    rows = await countRows();
    if (rows > 0) break;
  }
  // one automatic mid-run retry: fresh navigation with accumulated session state
  if (!retried && Date.now() - t0 > TIMEOUT/2) {
    retried = true;
    console.error('halfway, automatic retry with accumulated session state...');
    await send('Page.navigate', {url}, sessionId).catch(()=>{});
  }
}
if (!rows) {
  const title = await evalJS('document.title').catch(() => '?');
  const hasClearance = await clearance();
  fail(2, `WALLED after ${TIMEOUT/1000}s (challenge type: ${lastType}, cf_clearance issued: ${hasClearance}, page title: ${JSON.stringify(title)})`);
}

if (flag === '--selftest' && GENERIC) {
  const title = await evalJS('document.title').catch(()=>'?');
  console.log(`ROUTE OK: challenge cleared, page live (title: ${JSON.stringify(title)})`);
} else if (flag === '--selftest') {
  const titles = await evalJS("[...document.querySelectorAll('a.sr-torrent-link')].slice(0,3).map(a=>a.title)");
  const seeds = await evalJS("[...document.querySelectorAll('span.sr-seed')].slice(0,3).map(s=>s.textContent)");
  console.log(`UINDEX ROUTE OK: ${rows} rows rendered`);
  console.log('sample titles:', JSON.stringify(titles));
  console.log('sample seeds:', JSON.stringify(seeds));
} else {
  const table = await evalJS("document.querySelector('table.sr-table').outerHTML");
  process.stdout.write(table);
}
try { browser.kill('SIGKILL'); } catch {}
process.exit(0);
