import { makeAudioLoader } from './audio-src.js?v=20261027-f7-held-keys-r1';

const STATE_KEY = 'middots-state';
/* the sync service (service/ in the repo, a Cloudflare Worker); '' turns syncing off.
   The archive File never syncs: its viewer allows no outside requests or storage. */
const SYNC_URL = 'https://middots-sync.middots.workers.dev';

/* ==========================================================================
 * pieces - loads the archive content
 * --------------------------------------------------------------------------
 * The pieces themselves are data, not code: pieces.json, next to index.html,
 * is the one canonical source (the hosted archive File is built from the same
 * file). This module fetches it once at startup and hands App the list, newest
 * first. Each piece has an id, a title, a date stamp (YY.MM.DD HH:MM), its text
 * as blocks (a string is one paragraph, an array is a run of paragraphs), and
 * optional flags, note and voice recordings. Rendering lives in App.
 * ========================================================================== */

// Top-level await: App imports PIECES as a plain array, so the module holds the
// page back until the data has arrived. pieces.json sits next to index.html.
//
// Privacy: the public pieces.json carries only the project and its folders; its "pieces" list is
// empty, so a stranger opens an empty shelf. The published texts and recordings live encrypted in
// the owner's sync bucket (service/src/worker.ts, GET /archive and /audio) and are loaded here only
// when this browser has joined with that code.
const response = await fetch(new URL('./pieces.json', import.meta.url));
if (!response.ok) throw new Error(`pieces.json: HTTP ${response.status}`);
const data = await response.json();
const TOKEN_KEY$1 = 'middots-sync-token';
const token$1 = () => {
    try {
        return localStorage.getItem(TOKEN_KEY$1) ?? '';
    } catch {
        return '';
    }
};
/* Recordings stream from the bucket. The token never rides in the URL (a query
   token lands in the service's request logs and any copied link); audioSrc below
   fetches the bytes with the Authorization header and hands <audio> a blob URL.
   The plain URL is still the cache key - and useless to anyone without the token. */
const audioUrl = (file) => `${SYNC_URL}/audio/${encodeURIComponent(file.split('/').pop() ?? '')}`;
const audioLoader = makeAudioLoader({ baseUrl: SYNC_URL, token: token$1 });
const bridgeAudioLoader = makeAudioLoader({ baseUrl: `${SYNC_URL}/bridge/instinct`, token: token$1 });
const audioSrc = (u) => bridgeAudioLoader.isSyncAudio(u) ? bridgeAudioLoader.src(u) : audioLoader.src(u);
const toPiece = (p) => ({
    ...p,
    audio: (p.audio ?? []).map((a) => ({
        src: audioUrl(a.file),
        ...(Number.isInteger(a.afterParagraph) && a.afterParagraph > 0 ? { afterParagraph: a.afterParagraph } : {}),
        label: a.label,
    })),
});
/* All published pieces, newest first. One array for the page's whole life: joining fills it in
   place and leaving empties it, so every render reads the current shelf. */
/* the shelf rule: newest on top, by the piece's own date. The sort is stable, so equal stamps keep
   their given order. Stamps read YY.MM.DD HH:MM[:SS] [offset]; see stampKey. */
const STAMP_PARTS = /^(\d{2})\.(\d{2})\.(\d{2}) (\d{2}):(\d{2})(?::(\d{2}))?(?: ([+-])(\d{2})(?::(\d{2}))?)?$/;
const KEY_PAD = (n) => String(n).padStart(2, '0');
/* the sort key is the stamp's instant, so a stamp sealed at -04 and one sealed at +03 order by when
   they happened, not by their written clocks. It reads as a UTC stamp of the same shape. A stamp
   with no offset is a row from before offsets existed. Legacy policy: it counts as +03. That is
   exact for the published shelf (the archive schema defines its stamps as composition time,
   Istanbul time) and for any row sealed in Istanbul. The old nowStamp wrote the browser's own
   clock, so a legacy row sealed elsewhere (another profile's draft) is off by that writer's
   offset against newer rows; order among legacy rows, and among suffixed rows, stays exact.
   Display never uses this key. Anything else keeps its own text. */
const stampKey = (w) => {
    const s = String(w ?? '');
    const m = STAMP_PARTS.exec(s);
    if (!m) return s;
    const off = m[7] ? (m[7] === '-' ? -1 : 1) * (+m[8] * 60 + +(m[9] ?? 0)) : 180;
    const u = new Date(Date.UTC(2000 + +m[1], +m[2] - 1, +m[3], +m[4], +m[5], +(m[6] ?? 0)) - off * 60000);
    return `${KEY_PAD(u.getUTCFullYear() % 100)}.${KEY_PAD(u.getUTCMonth() + 1)}.${KEY_PAD(u.getUTCDate())} ${KEY_PAD(u.getUTCHours())}:${KEY_PAD(u.getUTCMinutes())}:${KEY_PAD(u.getUTCSeconds())}`;
};
const newestFirst = (list, dateOf) =>
    list
        .map((x, i) => [x, i])
        .sort((a, b) => {
            const ka = stampKey(dateOf(a[0]));
            const kb = stampKey(dateOf(b[0]));
            return ka < kb ? 1 : ka > kb ? -1 : a[1] - b[1];
        })
        .map((x) => x[0]);
/* a work piece's date: the oldest stamp among its versions, so editing never moves it */
const workDate = (wp) =>
    (wp.versions ?? []).map((v) => stampKey(v.born || v.when)).filter(Boolean).sort()[0] ?? '';
const sortedPieces = (list) => newestFirst(list.map(toPiece), (p) => p.when);
const PIECES = sortedPieces(data.pieces);
const closingInText = (lines) => lines.at(-1)?.trim() === '· ·';
/* Delete only the selected published piece. Read the live shelf first and verify the result. */
async function deletePrivate(id) {
    const t = token$1();
    if (!t) throw new Error('join a code before deleting');
    const headers = { Authorization: `Bearer ${t}` };
    const current = await fetch(`${SYNC_URL}/archive`, { headers, cache: 'no-store' });
    if (!current.ok) throw new Error('archive did not open');
    const archive = await current.json();
    if (!Array.isArray(archive.pieces) || !archive.pieces.some((p) => p.id === id))
        throw new Error('piece is not in the archive');
    const saved = { ...archive, pieces: archive.pieces.filter((p) => p.id !== id) };
    const r = await fetch(`${SYNC_URL}/archive`, {
        method: 'PUT',
        headers: { ...headers, 'Content-Type': 'application/json' },
        body: JSON.stringify(saved),
    });
    if (!r.ok) throw new Error('archive did not save');
    const checked = await fetch(`${SYNC_URL}/archive`, { headers, cache: 'no-store' });
    const readback = checked.ok ? await checked.json() : null;
    if (!Array.isArray(readback?.pieces) || readback.pieces.some((p) => p.id === id))
        throw new Error('archive readback did not match');
    PIECES.splice(0, PIECES.length, ...sortedPieces(readback.pieces));
}

let privateLoad = null;
async function loadPrivate() {
    const joinedToken = token$1();
    if (!joinedToken) return false;
    if (privateLoad?.token === joinedToken) return privateLoad.promise;
    const promise = (async () => {
        try {
            const r = await fetch(`${SYNC_URL}/archive`, {
                headers: { Authorization: `Bearer ${joinedToken}` }, cache: 'no-store',
            });
            if (!r.ok) return false;
            const a = await r.json();
            if (joinedToken !== token$1() || !Array.isArray(a.pieces)) return false;
            PIECES.splice(0, PIECES.length, ...sortedPieces(a.pieces));
            return true;
        } catch {
            /* offline: stay with what we have */
            return false;
        }
    })();
    privateLoad = { token: joinedToken, promise };
    try { return await promise; }
    finally { if (privateLoad?.promise === promise) privateLoad = null; }
}
/* After leaving: back to the public, empty shelf. */
function clearPrivate() {
    audioLoader.clear();
    bridgeAudioLoader.clear(); // the joined bucket's excerpts stop playing with the shelf
    PIECES.splice(0, PIECES.length, ...sortedPieces(data.pieces));
}
data.project;
const FOLDERS = data.folders;
/* which folder a piece lives in: its own "folder", or the first folder */
const folderOf = (p) => p.folder ?? FOLDERS[0].id;

export { FOLDERS, PIECES, STATE_KEY, SYNC_URL, audioSrc, clearPrivate, closingInText, deletePrivate, folderOf, loadPrivate, newestFirst, token$1, workDate };
