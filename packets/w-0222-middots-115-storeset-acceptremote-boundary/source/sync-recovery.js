/* Private recovery for sync merges and dictation text that could not be placed. Owner's own browser storage only:
 * nothing here is logged, sent, or written to a repo.
 * Recovery stores the supplied piece snapshots on this device. It is bounded to six entries and can fail when
 * storage is full. It does not preserve root-scalar differences: root-scalar deltas (state fields outside
 * pieces[]) are uncovered recovery scope. */
const KEY = 'middots-recovery';
const CAP = 6;
const read = () => { try { const value = JSON.parse(localStorage.getItem(KEY) || '[]'); return Array.isArray(value) ? value : []; } catch { return []; } };
const write = (list) => {
    for (let n = Math.min(list.length, CAP); n >= 1; n--) { // quota full: drop the OLDEST entries, never the new one
        try { const text = JSON.stringify(list.slice(0, n)); localStorage.setItem(KEY, text); return localStorage.getItem(KEY) === text; } catch { /* try fewer */ }
    }
    return false;
};
/* When even the minimal recovery write fails, the clashed text stays reachable with zero storage need:
 * inline in the note (bounded, expandable) and as a one-tap download. In-memory only - no new storage
 * key, no server call. Each entry lives until the user downloads it or dismisses the note. */
const fallbackEntries = []; // newest first, in-memory only
const FALLBACK_CAP = 3;
const INLINE_LIMIT = 4000;
const sideText = (label, pieces) => (Array.isArray(pieces) && pieces.length)
    ? label + ':\n' + pieces.map((p) => '== ' + (p.title || p.id || 'untitled') + ' ==\n' + ((p.versions ?? []).flatMap((v) => v.lines ?? [])).join('\n')).join('\n')
    : '';
const fallbackText = (entry) => [
    sideText('this device', entry.merged ?? entry.local),
    sideText('the newer online save', entry.remote),
].filter(Boolean).join('\n\n');
export function saveRecovery(entry) {
    const list = read();
    list.unshift({ at: new Date().toISOString(), ...entry });
    const ok = write(list);
    if (!ok) {
        fallbackEntries.unshift({ at: list[0].at, entry });
        if (fallbackEntries.length > FALLBACK_CAP) fallbackEntries.length = FALLBACK_CAP;
    }
    return ok;
}
/* Only the pieces named: a recovery entry is a copy of what clashed, not of the whole archive. */
export const piecesOf = (state, ids) => (state && Array.isArray(state.pieces) ? JSON.parse(JSON.stringify(state.pieces.filter((p) => ids.includes(p.id)))) : []);
export const listRecovery = () => read();
export function dropRecovery(index) { const list = read(); list.splice(index, 1); return write(list); }
/* A muted single line, deliberately quiet: no box, no native-styled dialog chrome, nothing that reads as a dialog.
   Same role=status and id contract as before; dismissal is a native <button> showing a bare x, keyboard-focusable
   with a visible :focus-visible outline; the mobile hit area comes from transparent padding, not a bigger glyph. */
export function showNote(text, id = 'sync-conflict-note') {
    if (typeof document === 'undefined') return null;
    const anchor = document.getElementById('sync-status-anchor');
    if (!anchor || !anchor.closest('main.page') || anchor.closest('[contenteditable],.controls,.story-head')) return null;
    let el = document.getElementById(id);
    if (el && el.parentNode !== anchor) { el.remove(); el = null; }
    if (!el) {
        const styleId = id + '-style'; // dismiss removes the note, not its style: reuse one fixed-id tag per note id (SN1 r3)
        let style = document.getElementById(styleId);
        if (!style) {
            style = document.createElement('style');
            style.id = styleId;
            style.textContent = '#' + id + ' button:focus-visible{outline:1px solid currentColor;outline-offset:2px}';
            document.head.appendChild(style);
        }
        el = document.createElement('div');
        el.id = id;
        el.setAttribute('role', 'status');
        el.style.cssText = 'box-sizing:border-box;max-width:100%;min-width:0;margin:.5em 0;overflow-wrap:anywhere;overflow-anchor:none;padding:0;background:none;color:var(--ink,#fff);opacity:.72;font:var(--fs-mono,10pt)/1.4 ui-monospace,monospace;display:grid;grid-template-columns:minmax(0,1fr) auto;align-items:start;gap:.2em';
        const msg = document.createElement('span'); msg.className = 'note-text'; msg.style.cssText='min-width:0;overflow-wrap:anywhere';
        const b = document.createElement('button'); b.type = 'button'; b.textContent = '\u00d7'; b.setAttribute('aria-label', 'dismiss sync note');
        b.style.cssText = 'background:none;border:0;color:inherit;font:inherit;cursor:pointer;padding:0 .55em;min-width:32px;min-height:32px;align-self:start'; // transparent padding = hit area, glyph unchanged
        b.addEventListener('click', () => el.remove());
        el.append(msg, b);
        anchor.appendChild(el);
    }
    const msg = el.querySelector('.note-text');
    if (msg.textContent !== text) msg.textContent = text; // repeated identical receipts do not announce twice
    /* On a failed recovery write the note itself keeps the clashed text reachable: the quota state is said
       plainly, the text shows inline (bounded, expandable), and one tap downloads it. The note still leaves
       only on explicit dismissal. */
    let fb = el.querySelector('.note-fallback');
    if (fallbackEntries.length && /recovery copy unavailable/.test(text)) {
        const entry = fallbackEntries[0];
        const full = fallbackText(entry.entry);
        if (!fb) {
            fb = document.createElement('span');
            fb.className = 'note-fallback';
            fb.style.cssText = 'grid-column:1 / -1;display:grid;gap:.2em;justify-items:start;min-width:0';
            const warn = document.createElement('span'); warn.className = 'note-fallback-warn';
            const det = document.createElement('details'); det.className = 'note-fallback-inline'; det.style.cssText = 'max-width:100%';
            const sum = document.createElement('summary'); sum.textContent = 'show the unsaved text'; sum.style.cssText = 'cursor:pointer';
            const pre = document.createElement('pre'); pre.className = 'note-fallback-text'; pre.style.cssText = 'margin:.2em 0;max-width:100%;max-height:40vh;overflow:auto;white-space:pre-wrap;overflow-wrap:anywhere;font:inherit';
            det.append(sum, pre);
            const dl = document.createElement('button'); dl.type = 'button'; dl.className = 'note-fallback-export';
            dl.style.cssText = 'background:none;border:0;color:inherit;font:inherit;cursor:pointer;padding:0 .55em 0 0;min-width:32px;min-height:32px;text-decoration:underline';
            fb.append(warn, det, dl);
            el.appendChild(fb);
        }
        fb.querySelector('.note-fallback-warn').textContent = "this device's storage is full - a recovery copy could not be kept. the differing text stays here until you download it or dismiss this note. (root-level settings are not included.)";
        fb.querySelector('.note-fallback-text').textContent = full.length > INLINE_LIMIT ? full.slice(0, INLINE_LIMIT) + '\n… (' + (full.length - INLINE_LIMIT) + ' more characters in the download)' : full;
        const dl = fb.querySelector('.note-fallback-export');
        dl.textContent = 'download the differing text';
        dl.onclick = () => {
            const url = URL.createObjectURL(new Blob([full], { type: 'text/plain' }));
            const a = document.createElement('a');
            a.href = url;
            a.download = 'middots-unsaved-' + entry.at.replace(/[:.]/g, '-') + '.txt';
            document.body.appendChild(a);
            a.click();
            a.remove();
            URL.revokeObjectURL(url); // object URL revoked right after the click
            fallbackEntries.shift();
            fb.remove();
        };
    } else if (fb) fb.remove();
    return el;
}

// One handling of each authenticated current-operation receipt. Old continuations are data, not work.
const handledMergeReceipts = new WeakSet();
export function handleMergeReceipt(res, merged, { current, retry, recover = saveRecovery, note = showNote }) {
    if (!res || !current(res) || handledMergeReceipts.has(res)) return;
    handledMergeReceipts.add(res);
    if (res.ok || res.kind === 'stale') return;
    if (res.kind === 'conflict' && res.status === 409) {
        const ids = (merged.pieces ?? []).filter(p => JSON.stringify(p) !== JSON.stringify((res.remote?.state?.pieces ?? []).find(q => q.id === p.id))).map(p => p.id);
        // Only differing pieces are retained; root scalars are explicitly not claimed as backed up.
        const saved = recover({ kind: 'push-conflict', merged: piecesOf(merged, ids), remote: piecesOf(res.remote?.state, ids) });
        if (current(res)) note('a newer save is online · this merge was not saved online' + (saved ? '' : ' · recovery copy unavailable'));
    } else if (res.kind === 'offline') retry(res);
}

export function clearSyncNotes() {
    if (typeof document === 'undefined') return;
    const anchor = document.getElementById('sync-status-anchor');
    if (anchor) anchor.replaceChildren();
}
