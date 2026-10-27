import { clearSyncNotes } from './sync-recovery.js?v=20261027-f7-held-keys-r1';
import { invalidateDurabilityIdentity, observeDurabilityIdentity } from './admin-transcribe-durability.js?v=20261027-f7-held-keys-r1';
import { SYNC_URL } from './pieces.js?v=20261027-f7-held-keys-r1';

/* The page's sync client. State and uploaded fonts are scoped to a joined code.
 * Pushes are delayed to reduce writes; a conflict pulls the newer service copy.
 * The Worker implementation is in service/src/worker.ts. */
const TOKEN_KEY = 'middots-sync-token';
const REV_KEY = 'middots-sync-rev';
const BASE_SCOPE_KEY = 'middots-sync-base-scope';
const BASE_KEY = 'middots-sync-base'; // the last copy known to match the service: the common ancestor for a merge
const PUSH_DELAY = 4000;
const SCROLL_PUSH_DELAY = 60000;
observeDurabilityIdentity(clearSyncNotes);
let stateWritesInFlight = 0;
// Private continuity and write receipts. Equal token/scope after a leave is not continuity.
let continuity = 0, writeGeneration = 0, pendingGeneration = 0, lastScheduledText;
const writeReceipts = new WeakMap();
const identity = () => ({ token: token(), scope: scope(), continuity });
const sameIdentity = c => !!c && c.token === token() && c.scope === scope() && c.continuity === continuity;
const beginWrite = () => ({ ...identity(), generation: ++writeGeneration, pendingGeneration });
const currentOperation = c => sameIdentity(c) && c.generation === writeGeneration && syncReady();
const writeResult = (c, value) => { const result = currentOperation(c) ? value : { ok: false, kind: 'stale', status: 0 }; writeReceipts.set(result, c); return result; };
// Presentation freshness is stricter than transport acceptance: a successful sent snapshot
// may advance the server base while a newer local snapshot waits to send.
function currentWrite(result) { const c = result && writeReceipts.get(result); return currentOperation(c) && c.pendingGeneration === pendingGeneration; }
// A failed explicit merge can restore only its own pending generation. A newer save wins.
function retryMerged(result) {
    const c = result && writeReceipts.get(result);
    if (!currentOperation(c) || result.kind !== 'offline' || pending !== null || pendingGeneration !== c.pendingGeneration) return false;
    schedulePush(c.state);
    return true;
}
const stateText = state => JSON.stringify(state);
const withoutScroll = state => {
    if (!state || typeof state !== 'object') return state;
    const {scroll, ...rest} = state;
    return rest;
};
const syncAvailable = () => true;
function read(key) {
    try {
        return localStorage.getItem(key) ?? '';
    } catch {
        return '';
    }
}
function write(key, v) {
    try {
        if (v) localStorage.setItem(key, v);
        else localStorage.removeItem(key);
        if (quotaWriteFailed) { quotaWriteFailed = false; recoveryChanged(); } // writes succeed again
    } catch {
        quotaWriteFailed = true; // Contract C(a): a full localStorage is no longer silent
        recoveryChanged();
    }
}
/* --- sync-quota-recovery r1 (SPEC 2026-10-18, Contracts B/C) -------------------------
   Unconfirmed piece edits get a recovery copy in IndexedDB, a SEPARATE quota bucket from
   the localStorage that fills up. A record is written before the push attempt and deleted
   when a push confirms that exact piece content. Steady state: the store is EMPTY. */
let quotaWriteFailed = false;
let lastConfirmed = null; // in-memory: quota can shed the localStorage base; confirmed content must not re-record
let recBroken = false; // Contract C(c): even the IDB copy could not be kept
const REC_DB = 'middots-recovery', REC_STORE = 'pieces', REC_MAX = 50, REC_BYTES = 2000000;
/* r2 privacy gate: every new record carries the sync profile's scope - a sha256 of the token,
   never the raw token. Legacy records without a scope stay stored, unseen, untouched. */
let scopeHashCache = { token: null, hash: null };
async function profileScope() {
    const t = token();
    if (!t) return null;
    if (scopeHashCache.token === t) return scopeHashCache.hash;
    try {
        const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode('middots-recovery-scope:' + t));
        scopeHashCache = { token: t, hash: [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('') };
    } catch { scopeHashCache = { token: t, hash: null }; }
    return scopeHashCache.hash;
}
const contentHash = (r) => { let h = 5381; const str = r.title + '\u0000' + JSON.stringify(r.lines); for (let i = 0; i < str.length; i++) h = ((h << 5) + h + str.charCodeAt(i)) >>> 0; return h.toString(36); };
const recoveryChanged = () => { try { window.dispatchEvent(new CustomEvent('middots-recovery')); } catch { } };
let recDbP = null;
function recDb() {
    if (!recDbP) recDbP = new Promise((res, rej) => {
        const q = indexedDB.open(REC_DB, 1);
        q.onupgradeneeded = () => q.result.createObjectStore(REC_STORE, { keyPath: 'pieceId' });
        q.onsuccess = () => res(q.result);
        q.onerror = () => rej(q.error);
    });
    return recDbP;
}
const recTx = (mode, fn) => recDb().then(db => new Promise((res, rej) => {
    const t = db.transaction(REC_STORE, mode), rq = fn(t.objectStore(REC_STORE));
    t.oncomplete = () => res(rq && rq.result);
    t.onerror = () => rej(t.error);
}));
async function recPut(rec) {
    try {
        const scope = await profileScope();
        if (!scope) return; // no verified profile: nothing is written rather than an unscoped record
        rec.scope = scope;
        const prev = await recTx('readonly', st => st.get(rec.pieceId)).catch(() => null);
        rec.ack = prev && prev.scope === scope && contentHash(prev) === contentHash(rec) ? (prev.ack ?? null) : null; // changed content re-announces
        await recTx('readwrite', st => st.put(rec));
        const all = await recAll(); // LRU cap: eviction still beats total loss
        let bytes = all.reduce((n, r) => n + JSON.stringify(r).length, 0);
        const byAge = [...all].sort((a, b) => a.at - b.at);
        for (const r of byAge) {
            if (all.length <= REC_MAX && bytes <= REC_BYTES) break;
            if (r.pieceId === rec.pieceId) continue; // never evict the record just written
            await recTx('readwrite', st => st.delete(r.pieceId));
            all.splice(all.indexOf(r), 1); bytes -= JSON.stringify(r).length;
            recoveryChanged(); // an eviction keeps the warning up
        }
    } catch { recBroken = true; }
    recoveryChanged();
}
const recAll = () => recTx('readonly', st => st.getAll()).catch(() => { recBroken = true; return []; }); // READ path: never dispatches (a dispatch here livelocks the rail listener)
/* A piece's live text: title plus the CURRENT version's lines (state-merge.js's shape). */
const pieceTitle = (p) => (p && p.title) || '';
const pieceLines = (p) => (p && Array.isArray(p.versions) && p.versions[p.current || 0] && p.versions[p.current || 0].lines) || [];
/* A record is confirmed when a push carries that exact piece content to the service. */
async function confirmRecovery(state) {
    const pcs = state && Array.isArray(state.pieces) ? state.pieces : [];
    const scope = await profileScope();
    for (const r of await recAll()) {
        if (!scope || r.scope !== scope) continue; // a push under this profile never drains another's records
        const p = pcs.find(x => x && x.id === r.pieceId);
        if (!p || pieceTitle(p) !== r.title || JSON.stringify(pieceLines(p)) !== JSON.stringify(r.lines)) continue;
        // conditional delete in ONE transaction: re-read before deleting, so a record replaced by a newer
        // unconfirmed edit while this confirm ran is never deleted from under it (write-before-confirm ordering)
        await recTx('readwrite', st => { const g = st.get(r.pieceId); g.onsuccess = () => { const cur = g.result; if (cur && cur.scope === scope && cur.title === r.title && JSON.stringify(cur.lines) === JSON.stringify(r.lines)) st.delete(r.pieceId); }; }).catch(() => { recBroken = true; });
    }
    recoveryChanged();
}
/* Pieces that differ from the push base get a recovery record BEFORE the push attempt. */
function recordUnconfirmed(state, base) {
    const bp = {}; for (const p of (base && base.pieces) || []) if (p && p.id) bp[p.id] = p;
    const cp = {}; for (const p of (lastConfirmed && lastConfirmed.pieces) || []) if (p && p.id) cp[p.id] = p;
    const matches = (q, p) => q && pieceTitle(q) === pieceTitle(p) && JSON.stringify(pieceLines(q)) === JSON.stringify(pieceLines(p));
    for (const p of (state && state.pieces) || []) {
        if (!p || !p.id) continue;
        // already-confirmed content is not an unconfirmed payload, even when the base was shed under quota
        if (matches(bp[p.id], p) || matches(cp[p.id], p)) continue;
        void recPut({ pieceId: p.id, title: pieceTitle(p), lines: pieceLines(p), at: Date.now(), revBasis: knownRev() });
    }
}
/* Contract B/C surface for the chrome: what is still unconfirmed on this device. */
async function recoveryStatus() {
    const scope = await profileScope();
    const records = (await recAll()).filter(r => scope && r.scope === scope);
    return {
        quota: quotaWriteFailed, broken: recBroken,
        records: records.map(r => ({ pieceId: r.pieceId, title: r.title, lines: r.lines, at: r.at, ack: r.ack ?? null, hash: contentHash(r) })),
        unack: records.filter(r => (r.ack ?? null) !== contentHash(r)).length,
    };
}
/* the owner saw the current copies: acknowledge each unchanged record once, by content hash + profile scope.
   A later content change clears the ack in recPut, so only changed content re-announces. */
async function recoveryAcknowledge() {
    const scope = await profileScope();
    if (!scope) return;
    for (const r of await recAll()) {
        if (r.scope !== scope) continue;
        const h = contentHash(r);
        if ((r.ack ?? null) !== h) await recTx('readwrite', st => st.put({ ...r, ack: h })).catch(() => { recBroken = true; });
    }
    recoveryChanged();
}

const isJoined = () => !!read(TOKEN_KEY);
const isMagicProfile = () => read(TOKEN_KEY).startsWith('ml1.');
/* A scoped one-use grant from a mailed wipe/e-mail-change link. Held in memory only. */
let heldGrant = null;
const hasGrant = () => heldGrant !== null;
const dropGrant = () => { heldGrant = null; };
const token = () => read(TOKEN_KEY);
const knownRev = () => Number(read(REV_KEY)) || 0;
// A persisted token is not evidence that this page read its remote state.
let readyToken = '', readyScope = '', archiveToken = '', archiveScope = '';
const readGrants = new WeakMap();
const scope = () => read(BASE_SCOPE_KEY);
const stateReady = () => !!token() && !!scope() && readyToken === token() && readyScope === scope();
const syncReady = () => stateReady() && archiveToken === token() && archiveScope === scope();
function acceptArchive(forToken) {
    if (!forToken || forToken !== token() || !scope()) return false;
    archiveToken = forToken; archiveScope = scope();
    return true;
}
function pauseStateWrites() {
    clearSyncNotes();
    continuity++; writeGeneration++; pendingGeneration++; lastScheduledText = undefined;
    invalidateDurabilityIdentity(); // private continuity ends on leave/adopt, even if a profile returns
    readyToken = ''; readyScope = ''; archiveToken = ''; archiveScope = '';
    pending = null;
    window.clearTimeout(timer);
}
function adoptToken(next) {
    pauseStateWrites();
    lastConfirmed = null; // r1.3 rider: confirmed content of the previous profile never crosses a login
    write(BASE_KEY, '');
    write(BASE_SCOPE_KEY, crypto.randomUUID());
    write(TOKEN_KEY, next); write(REV_KEY, '0');
}
function currentRead(r) {
    const grant = r && readGrants.get(r);
    return !!grant && grant.token === token() && grant.scope === scope() && grant.continuity === continuity && Number.isInteger(r.rev) && r.rev >= knownRev() && Object.hasOwn(r, 'state') && (r.state === null || (typeof r.state === 'object' && !Array.isArray(r.state)));
}
function remoteRead(rev, state, forToken, forScope, restoring = false) {
    const result = {rev, state, restoring};
    readGrants.set(result, {token: forToken, scope: forScope, continuity});
    return result;
}
async function call(path, init = {}) {
    return fetch(SYNC_URL + path, {
        ...init,
        headers: {
            ...(init.headers ?? {}),
            ...(token() ? { Authorization: `Bearer ${token()}` } : {}),
            ...(typeof init.body === 'string' ? { 'Content-Type': 'application/json' } : {}),
        },
    });
}
/* Capability read is fail-closed: a failed read never falls back to claiming. */
async function authMode(attempt) {
    let r;
    try { r=await call('/auth/config',{cache:'no-store'}); }
    catch { diagNote(attempt,'config','network-error'); return {unavailable:true, status:0}; }
    if (!r.ok) { diagNote(attempt,'config',String(r.status)); return {unavailable:true, status:r.status}; }
    try { const j=await r.json(); diagNote(attempt,'config',String(r.status)); return j; }
    catch { diagNote(attempt,'config',String(r.status)+' response-error'); return {unavailable:true, status:r.status}; }
}
/* Login attempt diagnostics: a fixed stage/status tuple only (config -> join -> state ->
   admin). Never code, token, body, headers or error text; 'network-error' marks a thrown
   fetch. Cleared at the next attempt. */
let loginAttempt = null;
let attemptSeq = 0; // memory-only attempt identity: never rendered, sent or logged
function diagNote(attempt, leg, value) {
    if (!attempt) return;
    attempt[leg] = value;
    if (attempt === loginAttempt) try { window.dispatchEvent(new CustomEvent('middots-login-diag')); } catch { }
}
function loginDiag() {
    return loginAttempt
        ? { config: loginAttempt.config, join: loginAttempt.join, state: loginAttempt.state, admin: loginAttempt.admin }
        : null;
}
function currentAttempt() {
    return loginAttempt; // memory handle for probe binding; never rendered, sent or logged
}
function noteAdminProbe(attempt, forToken, value) {
    if (attempt !== loginAttempt || forToken !== token()) return; // a stale probe (older attempt or older profile) never writes the current attempt
    diagNote(attempt, 'admin', value);
}
async function mailAction(purpose,code,email) {
    try {
        const r=await call(`/auth/${purpose}`,{method:'POST',body:JSON.stringify({code,email})});
        const body=await r.json();
        return r.ok ? {ok:true,...body} : {ok:false,error:body.error};
    } catch { return {ok:false,error:'the sync service did not answer'}; }
}
/* new address after the old address confirmed: the grant is the only credential */
async function bindEmail(email) {
    if(!heldGrant)return {ok:false,error:'link expired or used'};
    try {
        const r=await fetch(SYNC_URL+'/auth/email/start',{method:'POST',headers:{Authorization:`Bearer ${heldGrant}`,'Content-Type':'application/json'},body:JSON.stringify({email})});
        const body=await r.json().catch(()=>({}));
        if(!r.ok)return {ok:false,error:body.error};
        heldGrant=null;
        return {ok:true};
    } catch { return {ok:false,error:'the sync service did not answer'}; }
}
async function consumeMailLink() {
    const key=location.pathname.slice(1);
    if(!/^[A-Za-z0-9_-]{43}$/.test(key))return null;
    // Remove bearer capability before network calls, referrers or page history.
    history.replaceState(null,'','/'+location.hash);
    try {
        const r=await call('/auth/consume',{method:'POST',body:JSON.stringify({key})});
        const body=await r.json();
        if(!r.ok)return {ok:false,error:body.error};
        if(body.grant){heldGrant=body.grant;return {ok:true,purpose:body.purpose,grant:true};}
        if(body.changed||body.verified)return {ok:true,purpose:body.purpose||'email-new',changed:true};
        adoptToken(body.token);
        return {ok:true,created:body.created};
    } catch { return {ok:false,error:'the sync service did not answer'}; }
}
/* claim=false first: an unused code comes back as {unknown}, and the page asks before claiming it */
async function join(code, claim = false) {
    const mine = loginAttempt = { id: ++attemptSeq, config: '', join: '', state: '', admin: '', statePending: false };
    try {
        const capability=await authMode(mine);
        if(capability.unavailable)return {ok:false,error:"the sync service did not answer"};
        if(capability.email)claim=false;
        const r = await call('/join', {
            method: 'POST',
            body: JSON.stringify({ code, claim }),
        });
        let j;
        try {
            j = await r.json();
            diagNote(mine, 'join', String(r.status));
        } catch {
            diagNote(mine, 'join', String(r.status) + ' response-error');
            return { ok: false, error: 'the sync service did not answer' };
        }
        if (r.status === 404 && j.exists === false)
            return { ok: false, unknown: true, error: 'new code' };
        if (r.status === 429)
            return {
                ok: false,
                error: `wait ${Math.ceil(j.retryInSeconds / 60)} min`,
            };
        if (!r.ok) return { ok: false, error: j.error ?? `error ${r.status}` };
        adoptToken(j.token); // no previous profile base or pending save crosses this login
        mine.statePending = true; // the app pulls state right after a join
        return { ok: true, created: j.created, admin: !!j.admin };
    } catch {
        diagNote(mine, 'join', mine.join ? mine.join : 'network-error');
        return { ok: false, error: 'the sync service did not answer' };
    }
}
function leave() {
    pauseStateWrites();
    lastConfirmed = null; // r1.3 rider: a profile reset must not let old confirmed content skip recording
    write(BASE_SCOPE_KEY, '');
    write(TOKEN_KEY, '');
    write(REV_KEY, '');
    write(BASE_KEY, '');
}
const setBase = (state) => {
    try {
        if (!state) { localStorage.removeItem(BASE_KEY); return; }
        localStorage.setItem(BASE_KEY, JSON.stringify({scope: scope(), state}));
    } catch {
        // could not store it: a stale ancestor would mislead the next merge, none keeps both sides of any clash
        try { localStorage.removeItem(BASE_KEY); } catch { /* nothing more to do */ }
    }
};
const getBase = () => {
    if (!stateReady()) return null;
    try {
        const t = read(BASE_KEY);
        const saved = t ? JSON.parse(t) : null;
        return saved && saved.scope === scope() && scope() ? saved.state : null;
    } catch {
        return null;
    }
};
async function wipeProfile(code, byGrant = false) {
    try {
        if (byGrant && !heldGrant) return { ok: false, error: 'link expired or used' };
        const r = byGrant
            ? await fetch(SYNC_URL + '/profile', { method: 'DELETE', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ grant: heldGrant }) })
            : await call('/profile', { method: 'DELETE', body: JSON.stringify({ code }) });
        const j = await r.json().catch(() => ({}));
        // CANDIDATE: any non-ok answer after the DELETE left the page is an UNKNOWN outcome, never a
        // proof of non-application (O8/N1: a 4xx/403/429 sets the marker and never clears it)
        if (!r.ok) return { ok: false, unknown: true, error: j.error ?? `error ${r.status}` };
        window.clearTimeout(timer);
        pending = null; // a scheduled save must never revive the wiped profile
        heldGrant = null;
        leave();
        return { ok: true };
    } catch {
        return { ok: false, unknown: true, error: 'the sync service did not answer' };
    }
}
/* CANDIDATE: read-only receipt lookup for the held wipe grant (design F4). The answer 'applied' is
   the only post-fact clear (P1); every other answer leaves the marker untouched. */
async function wipeReceipt() {
    if (!heldGrant) return { ok: false, error: 'link expired or used' };
    try {
        const r = await fetch(SYNC_URL + '/auth/receipt', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ grant: heldGrant }) });
        const j = await r.json().catch(() => ({}));
        if (!r.ok) return { ok: false, error: j.error ?? `error ${r.status}` };
        return { ok: true, applied: j.applied === true };
    } catch {
        return { ok: false, error: 'the sync service did not answer' };
    }
}
async function changeCode(code, progress) {
    const capability=await authMode();
    if(capability.unavailable)return {ok:false,error:"the sync service did not answer"};
    if(capability.email || token().startsWith("ml1."))return {ok:false,emailRequired:true,error:"email verification required"};
    const step = async (name, extra = {}) => {
        const r = await call(`/rekey/${name}`, {
            method: 'POST',
            body: JSON.stringify({ code, ...extra }),
        });
        const j = await r.json().catch(() => ({}));
        if (r.status === 429) throw new Error(`wait ${Math.ceil(j.retryInSeconds / 60)} min`);
        if (!r.ok) throw new Error(j.error ?? `error ${r.status}`);
        return j;
    };
    try {
        await pushNow(); // nothing unsent is left behind on the old code
        const { keys } = await step('start');
        for (let i = 0; i < keys; i++) {
            progress(i, keys);
            await step('move', { i });
        }
        progress(keys, keys);
        const { token: next } = await step('finish');
        adoptToken(next);
        return { ok: true };
    } catch (e) {
        return {
            ok: false,
            error:
                e instanceof Error && e.message !== 'Failed to fetch'
                    ? e.message
                    : 'the sync service did not answer',
        };
    }
}
/* the page tells sync what to do when this device's code stops working (changed elsewhere) */
let onGone = () => {};
function onSignedOut(f) {
    onGone = f;
}
/* the service's copy, when it is newer than what this device last saw; null otherwise */
async function pull() {
    if (!isJoined()) return null;
    const forToken = token();
    if (!scope()) write(BASE_SCOPE_KEY, crypto.randomUUID());
    const forScope = scope();
    const forContinuity = continuity;
    const stillCurrent = () => token() === forToken && scope() === forScope && continuity === forContinuity;
    const armedAttempt = loginAttempt && loginAttempt.statePending ? loginAttempt : null;
    const noteState = (value) => {
        if (!armedAttempt || !armedAttempt.statePending) return;
        armedAttempt.statePending = false;
        diagNote(armedAttempt, 'state', value);
    };
    try {
        const r = await call('/state', { cache: 'no-store' });
        if (!stillCurrent()) return null;
        if (r.status === 401) {
            noteState('401');
            leave();
            onGone();
            return null;
        } // the code was changed on another device
        if (!r.ok) { noteState(String(r.status)); return null; }
        let j;
        try {
            j = await r.json();
            noteState(String(r.status));
        } catch {
            noteState(String(r.status) + ' response-error');
            return null;
        }
        if (!stillCurrent() || !j || !Number.isInteger(j.rev) || j.rev < 0
            || !Object.hasOwn(j, 'state') || (j.state !== null && (typeof j.state !== 'object' || Array.isArray(j.state)))) return null;
        const restoring = !syncReady();
        if (!restoring && (!j.state || j.rev <= knownRev())) return null;
        // Only a validated current-token read can reopen state writes after restore.
        return remoteRead(j.rev, j.state, forToken, forScope, restoring);
    } catch {
        noteState('network-error');
        return null;
    }
}
let timer;
let pending = null;
/* The page has merged this service copy with its own changes: only now does the known revision move. */
function acceptRemote(rev, state, reading) {
    if (!currentRead(reading) || reading.rev !== rev || reading.state !== state || rev < knownRev()) return false;
    writeGeneration++; // any earlier write continuation belongs to the previous accepted remote
    readyToken = token(); readyScope = scope();
    write(REV_KEY, String(rev));
    setBase(state);
    lastConfirmed = state;
    window.clearTimeout(timer);
    pending = null; // the merged state is pushed explicitly, once, by pushMerged
    return true;
}
/* One push of a merged state against the revision just accepted. No retry: a second conflict leaves the
   known revision where it was, so nothing is ever sent over a copy that was not merged. */
async function pushMerged(state, rev) {
    if (!syncReady()) return { ok: false, kind: 'stale', status: 0 };
    const c = beginWrite(); c.state = JSON.parse(stateText(state));
    stateWritesInFlight++;
    try {
        const r = await call('/state', { method: 'PUT', body: JSON.stringify({ baseRev: rev, state: c.state }) });
        const j = await r.json().catch(() => ({}));
        if (!currentOperation(c)) return writeResult(c, {});
        if (r.ok) {
            if (!Number.isInteger(j.rev) || j.rev < rev) return writeResult(c, { ok: false, kind: 'failed', status: r.status });
            write(REV_KEY, String(j.rev)); setBase(c.state);
            lastConfirmed = c.state;
            void confirmRecovery(c.state); // Contract B: merged push confirms its records too
            return writeResult(c, { ok: true, kind: 'saved', status: r.status, rev: j.rev });
        }
        return writeResult(c, { ok: false, kind: r.status === 409 ? 'conflict' : 'failed', status: r.status,
            remote: r.status === 409 ? remoteRead(j.rev, j.state, c.token, c.scope) : null });
    } catch {
        return writeResult(c, { ok: false, kind: 'offline', status: 0 });
    } finally { stateWritesInFlight--; }
}

let onRemote = () => {};
/* the page tells sync what to do when a newer copy arrives from another device */
function onNewer(apply) {
    onRemote = apply;
}
/* called on every local save; the push itself waits for a pause */
function schedulePush(state) {
    if (!syncReady()) return;
    const text = stateText(state);
    if (text !== lastScheduledText) { pendingGeneration++; lastScheduledText = text; }
    // Repeated renders must not reset an already-queued save or send duplicates.
    if (pending !== null && stateText(pending) === text) return;
    const base = getBase();
    // Do not suppress a revert while another version is in flight.
    if (!stateWritesInFlight && stateText(base) === text) {
        pending = null;
        window.clearTimeout(timer);
        return;
    }
    const scrollOnly = base && stateText(withoutScroll(base)) === stateText(withoutScroll(state));
    pending = JSON.parse(text); // freeze this save; later object mutation is not a newer save receipt
    recordUnconfirmed(pending, base); // Contract B: recovery copy BEFORE the push attempt
    window.clearTimeout(timer);
    // Text/settings retain their existing4s delay. Scroll-only reading movement
    // batches for60s; hidden-page flush still sends the final queued position.
    timer = window.setTimeout(() => void pushNow(), scrollOnly ? SCROLL_PUSH_DELAY : PUSH_DELAY);
}
/* One explicit reachability read for the admin status button. It shares the state
   request construction without accepting, rejecting, or mutating sync state. */
async function probeSync() {
    if (!isJoined()) return 'unconfigured';
    const controller = new AbortController();
    const timer = window.setTimeout(() => controller.abort(), 5000);
    try {
        await call('/state', { cache: 'no-store', signal: controller.signal });
        return 'online';
    } catch {
        return 'offline';
    } finally {
        window.clearTimeout(timer);
    }
}
async function pushNow(keepalive = false) {
    if (!syncReady() || pending === null) return;
    const c = beginWrite();
    const state = pending;
    pending = null;
    window.clearTimeout(timer);
    stateWritesInFlight++;
    try {
        const r = await call('/state', {
            method: 'PUT',
            body: JSON.stringify({ baseRev: knownRev(), state }),
            keepalive,
        });
        const j = await r.json();
        if (!currentOperation(c)) return;
        if (r.ok) {
            write(REV_KEY, String(j.rev));
            setBase(state);
            lastConfirmed = state;
            void confirmRecovery(state); // Contract B: the confirmed state drains its records
        } else if (r.status === 409) onRemote(remoteRead(j.rev, j.state, c.token, c.scope)); // merged by the page, never overwritten
    } catch {
        if (currentOperation(c) && pendingGeneration === c.pendingGeneration) pending = pending ?? state; /* same-profile offline save only */
    } finally {
        stateWritesInFlight--;
    }
}
async function listFonts() {
    const r = await call('/fonts', { cache: 'no-store' });
    if (!r.ok) throw new Error('font index unavailable');
    const body = await r.json();
    if (!body || !Array.isArray(body.fonts) || body.fonts.some(f => !f || typeof f.slug !== 'string'))
        throw new Error('font index unavailable');
    return body.fonts;
}
async function getFont(slug) {
    const r = await call(`/fonts/${slug}`, { cache: 'no-store' });
    if (!r.ok) throw new Error(`font ${r.status}`);
    return r.arrayBuffer();
}
async function putFont(f, data) {
    const q = new URLSearchParams({ name: f.name, file: f.file });
    const r = await call(`/fonts/${f.slug}?${q}`, { method: 'PUT', body: data });
    if (!r.ok) throw new Error(`font upload ${r.status}`);
}
async function deleteFont(slug) {
    await call(`/fonts/${slug}`, { method: 'DELETE' });
}

/* Uploaded font bytes stay private to the joined code on the sync service.
 * Without a joined code, uploads.js keeps them only in this browser. */
const SyncShare = {
    canRead: isJoined,
    list: listFonts,
    fetch: (f) => getFont(f.slug),
    put: putFont,
    remove: deleteFont,
};

async function recoveryRecordsScoped() {
    const scope = await profileScope();
    return (await recAll()).filter(r => scope && r.scope === scope);
}
export { recoveryStatus, recoveryAcknowledge, confirmRecovery, recordUnconfirmed, recoveryRecordsScoped as recoveryRecords, currentWrite, retryMerged, syncReady, acceptArchive, currentRead, probeSync, authMode, mailAction, consumeMailLink, SyncShare, changeCode, isJoined, join, leave, wipeProfile, onNewer, onSignedOut, pull, pushNow, wipeReceipt, acceptRemote, pushMerged, getBase, setBase, schedulePush, syncAvailable, token, isMagicProfile, hasGrant, dropGrant, bindEmail, loginDiag, noteAdminProbe, currentAttempt };

