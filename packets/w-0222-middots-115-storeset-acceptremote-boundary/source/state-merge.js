import { mergeAdminProfileState } from './admin-profile-state.js?v=20261027-f7-held-keys-r1';
/* Three-way merge of the saved page state: base (last copy known to match the service), local (this page now),
 * remote (the service's newer copy). Pure data in, data out: no DOM, no network, no storage.
 * Nothing is dropped silently: when both sides changed the same version, both texts are kept as separate versions;
 * when one side deleted what the other edited, the edit is kept. Anything of that kind sets conflicts[]. */
const eq = (a, b) => JSON.stringify(a ?? null) === JSON.stringify(b ?? null);
// Only typed admin no-op comparison ignores JSON object insertion order. Piece merge stays unchanged.
const adminCanon = value => Array.isArray(value) ? '[' + value.map(adminCanon).join(',') + ']' : value && typeof value === 'object' ? '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + adminCanon(value[key])).join(',') + '}' : JSON.stringify(value);
const sameAdmin = (a,b) => adminCanon(a) === adminCanon(b);
const clone = (v) => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
const hash6 = (s) => { let h = 5381; for (let i = 0; i < s.length; i++) h = ((h * 33) ^ s.charCodeAt(i)) >>> 0; return h.toString(36).slice(0, 6); };
const byId = (list, key) => new Map((Array.isArray(list) ? list : []).map((x) => [x?.[key], x]));
const curVid = (p) => p?.versions?.[p.current]?.vid;

function pick(base, local, remote) { // scalar or whole-value field: local wins only when this side changed it
    if (eq(local, base)) return clone(remote);
    return clone(local);
}

function mergeUiValue(base, local, remote) {
    if (local && remote && typeof local === 'object' && typeof remote === 'object' && !Array.isArray(local) && !Array.isArray(remote)) {
        const out = {};
        for (const key of new Set([...Object.keys(base ?? {}), ...Object.keys(local), ...Object.keys(remote)])) {
            const value = mergeUiValue(base?.[key], local[key], remote[key]);
            if (value !== undefined) Object.defineProperty(out, key, { value, enumerable: true, writable: true, configurable: true });
        }
        return out;
    }
    return pick(base, local, remote);
}

function mergeSnaps(b, l, r) {
    const seen = new Set(), out = [];
    for (const s of [...(r ?? []), ...(l ?? [])]) { const k = JSON.stringify(s); if (!seen.has(k)) { seen.add(k); out.push(s); } }
    return out;
}

function mergeVersion(b, l, r, ctx) {
    if (!b) { // added on both sides under the same vid
        if (eq(l, r)) return { v: clone(r) };
        return fork(l, r, ctx);
    }
    if (eq(l, b)) return { v: clone(r) };
    if (eq(r, b)) return { v: clone(l) };
    if (eq(l, r)) return { v: clone(l) };
    // both changed. Text edited on both sides, differently: keep both.
    const textL = !eq(l.lines, b.lines) || !eq(l.title, b.title), textR = !eq(r.lines, b.lines) || !eq(r.title, b.title);
    if (textL && textR && (!eq(l.lines, r.lines) || !eq(l.title, r.title))) return fork(l, r, ctx, b);
    const v = clone(textL ? l : r);
    v.snaps = mergeSnaps(b.snaps, l.snaps, r.snaps);
    if (!v.snaps.length) delete v.snaps;
    return { v };
}
function fork(l, r, ctx) {
    const extra = clone(l);
    extra.vid = `${l.vid}-m${hash6(JSON.stringify(l.lines) + String(l.title))}`;
    ctx.conflicts.push({ kind: 'same-version-edited', piece: ctx.piece, vid: l.vid, keptAs: extra.vid });
    return { v: clone(r), extra };
}

function mergePiece(b, l, r, ctx) {
    const c = { ...ctx };
    const bv = byId(b?.versions, 'vid'), lv = byId(l.versions, 'vid'), rv = byId(r.versions, 'vid');
    const order = [...(r.versions ?? []).map((v) => v.vid)];
    for (const v of l.versions ?? []) if (!order.includes(v.vid)) order.push(v.vid);
    const versions = [];
    const extras = new Map();
    for (const vid of order) {
        const B = bv.get(vid), L = lv.get(vid), R = rv.get(vid);
        if (L && R) { const m = mergeVersion(B, L, R, c); versions.push(m.v); if (m.extra) extras.set(vid, m.extra); }
        else if (L && !R) {
            if (!B) versions.push(clone(L));                      // new here
            else if (eq(L, B)) { /* removed there, untouched here: removal stands */ }
            else { versions.push(clone(L)); ctx.conflicts.push({ kind: 'remote-removed-local-edited', piece: ctx.piece, vid }); }
        } else if (R && !L) {
            if (!B) versions.push(clone(R));
            else if (eq(R, B)) { /* removed here, untouched there */ }
            else { versions.push(clone(R)); ctx.conflicts.push({ kind: 'local-removed-remote-edited', piece: ctx.piece, vid }); }
        }
    }
    for (const [vid, ex] of extras) { const at = versions.findIndex((v) => v.vid === vid); versions.splice(at + 1, 0, ex); }
    const out = {};
    for (const k of new Set([...Object.keys(b ?? {}), ...Object.keys(l), ...Object.keys(r)])) {
        if (k === 'versions' || k === 'current' || k === 'title') continue;
        const val = pick(b?.[k], l[k], r[k]);
        if (val !== undefined) out[k] = val;
    }
    out.versions = versions;
    const want = pick(curVid(b), curVid(l), curVid(r));
    let cur = versions.findIndex((v) => v.vid === want);
    if (cur < 0) cur = Math.min(Math.max(0, Number.isInteger(r.current) ? r.current : 0), Math.max(0, versions.length - 1));
    out.current = cur;
    if (versions[cur]) out.title = versions[cur].title;
    return out;
}

export function mergeStates(base, local, remote) {
    const conflicts = [], adminConflicts = [];
    if (!local || typeof local !== 'object') return { state: clone(remote), conflicts, adminConflicts, localChanged: false };
    if (!remote || typeof remote !== 'object') return { state: clone(local), conflicts, adminConflicts, localChanged: true };
    const B = base && typeof base === 'object' ? base : null;
    const out = {};
    const keys = new Set([...Object.keys(B ?? {}), ...Object.keys(local), ...Object.keys(remote)]);
    for (const k of keys) {
        if (k === 'pieces') continue;
        if (k === 'adminProfiles') {
            const m = mergeAdminProfileState({ base: B?.[k] ?? null, local: local[k] ?? null, remote: remote[k] ?? null });
            if (m.held) { if (remote[k] !== undefined) out[k] = clone(remote[k]); }
            else if (m.value) out[k] = sameAdmin(m.value, remote[k]) ? clone(remote[k]) : m.value;
            if (m.held || m.conflicts.length) adminConflicts.push({ reason: m.reason, conflicts: m.conflicts, held: m.held }); // raw custody by reference, never trimmed
            continue;
        }
        if (k === 'uiPresets' || k === 'open') {
            /* a side lacking the key never learned it (a save from an older build): keep the side
               that knows, same rule as the share registry. */
            if (local[k] === undefined && remote[k] === undefined) { if (B?.[k] !== undefined) out[k] = clone(B[k]); continue; }
            if (local[k] === undefined) { out[k] = clone(remote[k]); continue; }
            if (remote[k] === undefined) { out[k] = clone(local[k]); continue; }
            /* No shared ancestor for this value (first restore, fresh scope, or a base written
               before the key existed): nothing can prove the local copy is newer, and boot
               defaults always carry indexHidden:false. Local-wins here silently reverted the
               confirmed remote choices, and the next ordinary save pushed that loss to every
               device (admin presets 2026-10-23/24). The confirmed remote wins; UI flags are
               re-derivable on the one device that truly changed them. */
            if (B?.[k] === undefined) { out[k] = clone(remote[k]); continue; }
            out[k] = mergeUiValue(B?.[k], local[k], remote[k]); continue;
        }
        let val;
        if (['folders', 'goneFolders'].includes(k) && Array.isArray(local[k]) && Array.isArray(remote[k])) {
            const seen = new Set(); val = [];
            for (const x of [...remote[k], ...local[k]]) { const id = JSON.stringify(x?.id ?? x); if (!seen.has(id)) { seen.add(id); val.push(clone(x)); } }
        } else if (k === 'folderNames' && local[k] && remote[k] && typeof local[k] === 'object') {
            val = { ...clone(remote[k]) };
            for (const [fk, fv] of Object.entries(local[k])) if (!eq(fv, B?.[k]?.[fk])) val[fk] = clone(fv);
        } else val = pick(B?.[k], local[k], remote[k]);
        if (val !== undefined) out[k] = val;
    }
    const bp = byId(B?.pieces, 'id'), lp = byId(local.pieces, 'id'), rp = byId(remote.pieces, 'id');
    const pieces = [];
    const order = [...(remote.pieces ?? []).map((p) => p.id)];
    for (const p of local.pieces ?? []) if (!order.includes(p.id)) order.push(p.id);
    for (const id of order) {
        const b = bp.get(id), l = lp.get(id), r = rp.get(id);
        if (l && r) {
            if (eq(l, r)) pieces.push(clone(r));
            else if (b && eq(l, b)) pieces.push(clone(r));
            else if (b && eq(r, b)) pieces.push(clone(l));
            else pieces.push(mergePiece(b, l, r, { conflicts, piece: id }));
        } else if (l && !r) {
            if (!b) pieces.push(clone(l));
            else if (eq(l, b)) { /* removed remotely, untouched here */ }
            else { pieces.push(clone(l)); conflicts.push({ kind: 'remote-removed-local-edited', piece: id }); }
        } else if (r && !l) {
            if (!b) pieces.push(clone(r));
            else if (eq(r, b)) { /* removed here, untouched there */ }
            else { pieces.push(clone(r)); conflicts.push({ kind: 'local-removed-remote-edited', piece: id }); }
        }
    }
    out.pieces = pieces;
    return { state: out, conflicts, adminConflicts, localChanged: !eq(out, remote) };
}

