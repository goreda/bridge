#!/usr/bin/env node
// gofile_folder.mjs - resolves a gofile folder link to its real file listing.
// Rides the gofile frontend inside real Chrome (persistent trained profile):
// loads the folder page, sniffs the frontend's own api.gofile.io calls via CDP,
// and returns the contents JSON the site itself received. No wt extraction, no
// deobfuscation - sustainable against frontend token rotation.
// usage: node gofile_folder.mjs <chrome-path> <folder-url>
// env: BRIDGE_USER_DATA_DIR (profile), BRIDGE_TIMEOUT (ms, default 90000)
import {spawn} from 'node:child_process';
import {connect} from 'node:net';
import {randomBytes} from 'node:crypto';
import http from 'node:http';

const [chromePath, folderUrl] = process.argv.slice(2);
if (!chromePath || !folderUrl) { console.error('usage: node gofile_folder.mjs <chrome> <folder-url>'); process.exit(64); }
const TIMEOUT = Number(process.env.BRIDGE_TIMEOUT) || 90000;
const PROFILE = process.env.BRIDGE_USER_DATA_DIR || (process.env.HOME + '/.gor/browser-profile');
const HEADLESS = process.env.BRIDGE_HEADLESS === '1'; // headed+offscreen default (trained-profile behavior)

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
  let buf = Buffer.alloc(0);
  return (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    const out = [];
    while (buf.length >= 2) {
      const len0 = buf[1] & 0x7f;
      const off = len0 < 126 ? 2 : len0 === 126 ? 4 : 10;
      const len = len0 < 126 ? len0 : len0 === 126 ? buf.readUInt16BE(2) : Number(buf.readBigUInt64BE(2));
      if (buf.length < off + len) break;
      out.push(buf.subarray(off, off + len).toString());
      buf = buf.subarray(off + len);
    }
    return out;
  };
};
const getJSON = (port, path) => new Promise((res, rej) => {
  http.get({host: '127.0.0.1', port, path}, r => {
    let b = ''; r.on('data', c => b += c); r.on('end', () => { try { res(JSON.parse(b)); } catch (e) { rej(e); } });
  }).on('error', rej);
});

const args = [
  '--remote-debugging-port=0', '--user-data-dir=' + PROFILE,
  '--disable-blink-features=AutomationControlled', '--no-first-run', '--no-default-browser-check',
  ...(HEADLESS ? ['--headless=new'] : ['--window-position=3000,3000', '--window-size=1200,900']),
  'about:blank',
];
const browser = spawn(chromePath, args, {stdio: ['ignore', 'pipe', 'pipe']});
let stderrBuf = '';
browser.stderr.on('data', d => { stderrBuf += d; });
const fail = (code, msg) => { console.error(msg); try { browser.kill('SIGKILL'); } catch {} process.exit(code); };
browser.on('error', e => fail(66, 'spawn: ' + e.message));
const killer = setTimeout(() => fail(75, 'TIMEOUT after ' + TIMEOUT + 'ms'), TIMEOUT);

const wsLine = await new Promise((res, rej) => {
  const on = d => { const m = d.toString().match(/DevTools listening on (ws:\/\/\S+)/); if (m) { browser.stderr.off('data', on); res(m[1]); } };
  browser.stderr.on('data', on);
  setTimeout(() => rej(new Error('no DevTools line')), 15000);
}).catch(e => fail(66, e.message));
const wsURL = new URL(wsLine);
const port = Number(wsURL.port);
const targets = await getJSON(port, '/json/list');
const page = targets.find(t => t.type === 'page');
if (!page) fail(66, 'no page target');
const {sock, rest} = await wsHandshake(port, new URL(page.webSocketDebuggerUrl).pathname).catch(e => fail(66, 'ws connect: ' + e.message));

let mid = 0; const pending = new Map();
const send = (method, params = {}) => new Promise((res, rej) => {
  const id = ++mid; pending.set(id, {res, rej});
  sock.write(encodeFrame(JSON.stringify({id, method, params})));
});
const apiRequests = new Map(); // requestId -> {url, headers}
let bearer = null, acctCookie = null, siteToken = null, xbl = null;
const contentsPages = new Map(); // requestId -> body
let contentsReq = null, lastContentsAt = 0;
const parse = frameParser();
const onChunk = (chunk) => {
  for (const text of parse(chunk)) {
    let msg; try { msg = JSON.parse(text); } catch { continue; }
    if (msg.id && pending.has(msg.id)) { const p = pending.get(msg.id); pending.delete(msg.id); msg.error ? p.rej(new Error(msg.error.message)) : p.res(msg.result); continue; }
    if (msg.method === 'Network.requestWillBeSentExtraInfo') {
      const h = msg.params.headers || {};
      const auth = h.authorization || h.Authorization;
      if (auth && auth.startsWith('Bearer ')) bearer = auth;
      if (h['x-website-token']) siteToken = h['x-website-token'];
      if (h['x-bl']) xbl = h['x-bl'];
    }
    if (msg.method === 'Network.requestWillBeSent') {
      const u = msg.params.request.url;
      if (u.includes('api.gofile.io')) {
        apiRequests.set(msg.params.requestId, {url: u, headers: msg.params.request.headers});
        const h = msg.params.request.headers || {};
        if (h.Authorization) bearer = h.Authorization;
        if (h['x-website-token']) siteToken = h['x-website-token'];
        if (h['x-bl']) xbl = h['x-bl'];
        if (h.Cookie && !acctCookie) acctCookie = h.Cookie;
      }
    }
    if (msg.method === 'Network.responseReceived') {
      const u = msg.params.response.url;
      if (u.includes('api.gofile.io') && u.includes('/contents/')) {
        send('Network.getResponseBody', {requestId: msg.params.requestId}).then(r => {
          if (r && r.body) { contentsPages.set(msg.params.requestId, r.body); contentsReq = apiRequests.get(msg.params.requestId) || contentsReq; lastContentsAt = Date.now(); }
        }).catch(() => {});
      }
    }
  }
};
if (rest.length) onChunk(rest);
sock.on('data', onChunk);

await send('Network.enable');
await send('Page.enable');
await send('Page.addScriptToEvaluateOnNewDocument', {source: 'Object.defineProperty(navigator,"webdriver",{get:()=>undefined});'});
await send('Page.navigate', {url: folderUrl});

const deadline = Date.now() + TIMEOUT - 3000;
// wait for first contents response, then keep collecting until 2.5s quiet (catches pagination)
while (Date.now() < deadline) {
  await new Promise(r => setTimeout(r, 500));
  if (contentsPages.size > 0 && Date.now() - lastContentsAt > 2500) break;
}
clearTimeout(killer);

if (!contentsPages.size) {
  const seen = [...apiRequests.values()].map(x => x.url);
  fail(75, 'NO_CONTENTS: no api.gofile.io/contents response captured. api calls seen: ' + JSON.stringify(seen));
}
const byId = new Map(); let meta = null;
for (const body of contentsPages.values()) {
  let parsed; try { parsed = JSON.parse(body); } catch { continue; }
  if (parsed.status !== 'ok') continue;
  const d = parsed.data || {};
  if (!meta && d.id) meta = {id: d.id, name: d.name, type: d.type, totalSize: d.totalSize ?? null, childrenCount: d.childrenCount ?? null};
  for (const c of Object.values(d.children || {})) {
    byId.set(c.id, {id: c.id, code: c.code ?? null, name: c.name, type: c.type, size: c.size ?? null, link: c.link ?? null, directLink: c.directLink ?? null});
  }
}
if (!meta) fail(70, 'no ok contents response in captured pages');
const kids = [...byId.values()];
// expand nested subfolders by replaying the contents call INSIDE the page
// (page context carries cf_clearance + account cookies; Node replay is refused)
const expand = async (kid, depth) => {
  if (kid.type !== 'folder' || depth > 4) return;
  const cid = kid.code || kid.id;
  const hdrs = {Authorization: bearer || ''};
  if (siteToken) hdrs['x-website-token'] = siteToken;
  if (xbl) hdrs['x-bl'] = xbl;
  const expr = `fetch('https://api.gofile.io/contents/${cid}?page=1&pageSize=100&sortField=name&sortDirection=1',{credentials:'include',headers:${JSON.stringify(hdrs)}}).then(r=>r.json()).catch(e=>({status:'fetch_failed'}))`;
  const r = await send('Runtime.evaluate', {expression: expr, awaitPromise: true, returnByValue: true}).catch(() => null);
  const j = r && r.result && r.result.value;
  if (!j || j.status !== 'ok') { kid.expandError = (j && j.status) || 'bad_response'; return; }
  kid.children = [];
  for (const c of Object.values((j.data && j.data.children) || {})) {
    const sub = {id: c.id, code: c.code ?? null, name: c.name, type: c.type, size: c.size ?? null, link: c.link ?? null, directLink: c.directLink ?? null};
    kid.children.push(sub);
    await expand(sub, depth + 1);
  }
};
if (bearer) for (const k of kids) await expand(k, 0);
try { browser.kill('SIGKILL'); } catch {}
console.log(JSON.stringify({
  status: 'ok', folder: meta,
  children: kids, pages: contentsPages.size,
  truncated: !!(meta.childrenCount && kids.length < meta.childrenCount),
  apiCall: contentsReq ? {url: contentsReq.url, hasAuth: !!(contentsReq.headers && (contentsReq.headers.Authorization || contentsReq.headers.authorization))} : null,
}, null, 1));
process.exit(0);
