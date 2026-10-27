/* Account-bound admin layout profiles (owner block 90a2).
 * middots-admin-typography / middots-admin-layout-profiles become a server-side, per-account,
 * versioned field (`adminProfiles`) inside the EXISTING encrypted state document (no new
 * service or env). Restored on any browser after login; existing local values WIN on first
 * upload (no reset). Lanes: desktop and mobile are isolated layout types; EACH lane syncs.
 *
 * PURE module: no DOM, no storage, no fetch, no timers. The App/sync layer wires it
 * (peer 90a1 owns App integration). Nothing here is an authority oracle: adminVerified,
 * binding tags, firstUpload and editWitness are INPUTS the caller must ground in the actual
 * session and in ACTUAL edit events. A non-null `value` is a STORAGE candidate, never a
 * hydration or disclosure permission: the caller applies it only under its own verified
 * session (results carry applyRequiresVerifiedSession when adminVerified was not true).
 *
 * Field list verified against the SERVED App (8b53c10d, app.js:251-281 adminType lane):
 * textFace, indexFace, textPt, indexPt, textAxes, indexAxes, lh, hz, textWidthEm.
 * deviceLane is session state and is NEVER serialized. UI hover/taste state never enters.
 * Clamping is the App's display concern (controls.js); this module validates TYPES.
 *
 * Trust posture: any invalid KNOWN field makes its lane CORRUPT as a whole - partial
 * acceptance of a typed-invalid lane could mix incompatible versions. Corrupt remote/local
 * is HELD (raw bytes preserved, nothing written), never treated as absent, never merged.
 * Unknown fields are preserved through a deep JSON-safe copy (forward compat) with
 * prototype-polluting keys rejected at EVERY level and non-plain objects refused.
 *
 * STRICT consumption: unsafe content ANYWHERE - state root, lane root, known or unknown
 * field, any nesting depth - makes the whole state CORRUPT: merge/prepare HOLD with the
 * raw bytes in `held` and NEVER write a trimmed copy over the source. Sanitizing held or
 * foreign data for DISPLAY is the caller's own separate concern.
 * `held` preserves the raw inputs BY REFERENCE on purpose (unsafe bytes cannot be deep
 * copies); `value` and `conflicts` never alias each other, the inputs, or `held`. */

export const ADMIN_PROFILE_STATE_VERSION = 1;
export const ADMIN_PROFILE_FIELDS = Object.freeze(['textFace', 'indexFace', 'textPt', 'indexPt', 'textAxes', 'indexAxes', 'lh', 'hz', 'textWidthEm']);
const LANES = Object.freeze(['desktop', 'mobile']);
const FORBIDDEN_KEYS = new Set(['__proto__', 'constructor', 'prototype']);
const MAX_DEPTH = 32;

const isPlainObject = (v) => {
    if (typeof v !== 'object' || v === null || Array.isArray(v)) return false;
    const p = Object.getPrototypeOf(v);
    return p === Object.prototype || p === null;             // Date/class instances refused
};
const isSafeKey = (k) => !FORBIDDEN_KEYS.has(k);

/* Deep JSON-safe COPY of an unknown (forward-compat) value. null when the value cannot be
 * represented safely: functions, undefined, non-finite numbers, non-plain objects, cycles or
 * nesting past MAX_DEPTH, forbidden keys at any depth. */
const deepSafe = (v, depth = 0) => {
    if (depth > MAX_DEPTH) return { ok: false };
    if (v === null || typeof v === 'boolean' || typeof v === 'string') return { ok: true, value: v };
    if (typeof v === 'number') return Number.isFinite(v) ? { ok: true, value: v } : { ok: false };
    if (Array.isArray(v)) {
        const out = [];
        for (const item of v) { const r = deepSafe(item, depth + 1); if (!r.ok) return { ok: false }; out.push(r.value); }
        return { ok: true, value: out };
    }
    if (isPlainObject(v)) {
        const out = {};
        for (const [k, item] of Object.entries(v)) {
            if (!isSafeKey(k)) return { ok: false };
            const r = deepSafe(item, depth + 1); if (!r.ok) return { ok: false };
            out[k] = r.value;
        }
        return { ok: true, value: out };
    }
    return { ok: false };
};

/* Structural deep equality over JSON-safe values, key order ignored. */
const canon = (v) => {
    if (Array.isArray(v)) return '[' + v.map(canon).join(',') + ']';
    if (isPlainObject(v)) return '{' + Object.keys(v).sort().map(k => JSON.stringify(k) + ':' + canon(v[k])).join(',') + '}';
    return JSON.stringify(v) ?? 'undefined';
};
const same = (a, b) => canon(a) === canon(b);

const cleanAxes = (v) => {
    if (!isPlainObject(v)) return null;
    const out = {};
    for (const [face, axes] of Object.entries(v)) {
        if (!isSafeKey(face) || !isPlainObject(axes)) return null;
        const inner = {};
        for (const [axis, val] of Object.entries(axes)) {
            if (!isSafeKey(axis) || typeof val !== 'number' || !Number.isFinite(val)) return null;
            inner[axis] = val;
        }
        out[face] = inner;
    }
    return out;
};
const FIELD_CLEANERS = {
    textFace: v => (typeof v === 'string' ? v : null),
    indexFace: v => (typeof v === 'string' ? v : null),
    textPt: v => (typeof v === 'number' && Number.isFinite(v) ? v : null),
    indexPt: v => (typeof v === 'number' && Number.isFinite(v) ? v : null),
    textAxes: cleanAxes,
    indexAxes: cleanAxes,
    lh: v => (typeof v === 'number' && Number.isFinite(v) ? v : null),
    hz: v => (typeof v === 'number' && Number.isFinite(v) ? v : null),
    textWidthEm: v => (typeof v === 'number' && Number.isFinite(v) ? v : null),
};

/* STRICT: a lane is a clean DEEP COPY of the input, or null when the lane is not a plain
 * object, is empty, or ANY known field fails its type check. Unknown fields are preserved
 * only when deepSafe. deviceLane is session state, never serialized. */
export function cleanLane(value) {
    if (!isPlainObject(value)) return null;
    const out = {};
    for (const [k, v] of Object.entries(value)) {
        if (!isSafeKey(k)) return null;                                 // strict: pollution keys corrupt the lane
        if (k === 'deviceLane') continue;
        const cleaner = FIELD_CLEANERS[k];
        if (cleaner) { const c = cleaner(v); if (c === null) return null; out[k] = c; continue; }
        const r = deepSafe(v);
        if (!r.ok) return null;                                      // strict: unsafe unknown content corrupts the lane
        out[k] = r.value;
    }
    return Object.keys(out).length ? out : null;
}

export function cleanAdminProfileState(value) {
    if (!isPlainObject(value)) return null;
    if (value.version !== ADMIN_PROFILE_STATE_VERSION) return null;
    for (const k of Object.keys(value)) if (!isSafeKey(k)) return null;             // strict: root pollution keys
    if (!isPlainObject(value.profiles)) return null;
    for (const k of Object.keys(value.profiles)) if (!isSafeKey(k)) return null;
    const profiles = {};
    for (const [lane, raw] of Object.entries(value.profiles)) {
        if (LANES.includes(lane)) {
            const clean = cleanLane(raw);
            if (clean === null && raw !== null && raw !== undefined) return null;  // a corrupt lane corrupts the state
            if (clean) profiles[lane] = clean;
        } else {
            // Unknown FUTURE lane: preserved verbatim through a strict deep copy - never
            // trimmed, never lane-validated (its field semantics are not ours); unsafe
            // content corrupts the whole state.
            const r = deepSafe(raw);
            if (!r.ok) return null;
            profiles[lane] = r.value;
        }
    }
    if (!Object.keys(profiles).length) return null;
    const state = { version: ADMIN_PROFILE_STATE_VERSION, profiles };
    for (const [k, v] of Object.entries(value)) {                       // unknown ROOT fields preserved (strict deep copy)
        if (k === 'version' || k === 'profiles') continue;
        const r = deepSafe(v);
        if (!r.ok) return null;
        state[k] = r.value;
    }
    return state;
}

/* Typed status: 'absent' (key genuinely missing) vs 'corrupt' (present but unreadable,
 * INCLUDING a partially-invalid lane) vs 'valid'. CORRUPT IS NOT ABSENT. */
export function remoteStatus(remote) {
    if (remote === null || remote === undefined) return { status: 'absent', value: null };
    const value = cleanAdminProfileState(remote);
    return value ? { status: 'valid', value } : { status: 'corrupt', value: null };
}

const holdRemote = (remote, local) => ({ value: null, held: { remote, local }, reason: 'remote-corrupt-held', conflicts: [] });
const holdBase = (base, local, remote) => ({ value: null, held: { base, local, remote }, reason: 'base-corrupt-held', conflicts: [] });

/* Generic 3-way rule for ONE value (root extra or unknown-lane): the same absence/conflict
 * rules as lane fields - no deletes on one-sided absence, base-only preserved, additive kept,
 * ancestorless or both-moved divergence keeps the approved REMOTE and records a conflict. */
const pick3 = (scope, key, inB, bv, inL, lv, inR, rv, conflicts) => {
    if (inL && inR && same(lv, rv)) return { has: true, v: lv };
    if (inB) {
        if (inR && same(bv, rv) && inL) return { has: true, v: lv };
        if (inL && same(bv, lv) && inR) return { has: true, v: rv };
        if (inR && !inL) return { has: true, v: rv };
        if (inL && !inR) return { has: true, v: lv };
        if (inL && inR) { conflicts.push({ scope, field: key, local: deepSafe(lv).value, remote: deepSafe(rv).value }); return { has: true, v: rv }; }
        return { has: true, v: bv };
    }
    if (inL && !inR) return { has: true, v: lv };
    if (inR && !inL) return { has: true, v: rv };
    if (inL && inR) { conflicts.push({ scope, field: key, local: deepSafe(lv).value, remote: deepSafe(rv).value }); return { has: true, v: rv }; }
    return { has: false };
};
const holdLocal = (local, remote) => ({ value: null, held: { local, remote }, reason: 'local-corrupt-held', conflicts: [] });

/* Three-way merge per lane per field, over STRICTLY cleaned inputs. A corrupt remote or local
 * is a HOLD with the raw bytes preserved - never silently treated as absent. Missing root or
 * field means UNKNOWN - never a delete, never a default; a field only the base knew is
 * PRESERVED from the base (its absence on both sides is not proof of deletion).
 * Divergence without an ancestor keeps the approved REMOTE value and records BOTH candidates
 * in `conflicts` (private audit data - never rendered, exported, or synced). */
export function mergeAdminProfileState({ base = null, local = null, remote = null } = {}) {
    const rs = remoteStatus(remote);
    if (rs.status === 'corrupt') return holdRemote(remote, local);
    if (local !== null && local !== undefined && cleanAdminProfileState(local) === null) return holdLocal(local, remote);
    const bState = cleanAdminProfileState(base);
    if (base !== null && base !== undefined && bState === null) return holdBase(base, local, remote);   // corrupt PRESENT base: typed hold, raw preserved
    const lState = cleanAdminProfileState(local);
    const b = bState?.profiles || {};
    const l = lState?.profiles || {};
    const r = rs.value?.profiles || {};
    const conflicts = [];
    const profiles = {};
    const laneKeys = new Set([...Object.keys(b), ...Object.keys(l), ...Object.keys(r)]);
    for (const lane of laneKeys) {
        if (!LANES.includes(lane)) {                                                    // unknown future lane: 3-way whole-value
            const pick = pick3('profiles', lane, lane in b, b[lane], lane in l, l[lane], lane in r, r[lane], conflicts);
            if (pick.has) profiles[lane] = pick.v;
            continue;
        }
        const bl = b[lane] || {}, ll = l[lane] || {}, rl = r[lane] || {};
        const fields = new Set([...Object.keys(bl), ...Object.keys(ll), ...Object.keys(rl)]);
        const out = {};
        for (const f of fields) {
            const inB = f in bl, inL = f in ll, inR = f in rl;
            if (inL && inR && same(ll[f], rl[f])) { out[f] = ll[f]; continue; }
            if (inB) {
                if (inR && same(bl[f], rl[f]) && inL) { out[f] = ll[f]; continue; }      // only local moved
                if (inL && same(bl[f], ll[f]) && inR) { out[f] = rl[f]; continue; }      // only remote moved
                if (inR && !inL) { out[f] = rl[f]; continue; }                           // local unknown: no delete
                if (inL && !inR) { out[f] = ll[f]; continue; }                           // remote unknown: no delete
                if (inL && inR) { out[f] = rl[f]; conflicts.push({ lane, field: f, local: deepSafe(ll[f]).value, remote: deepSafe(rl[f]).value }); continue; }
                out[f] = bl[f];                                                          // base-only: preserved, not dropped
                continue;
            }
            if (inL && !inR) { out[f] = ll[f]; continue; }                               // additive local field
            if (inR && !inL) { out[f] = rl[f]; continue; }                               // additive remote field
            out[f] = rl[f];                                                              // ancestorless divergence
            conflicts.push({ lane, field: f, local: deepSafe(ll[f]).value, remote: deepSafe(rl[f]).value });
        }
        if (Object.keys(out).length) profiles[lane] = out;
    }
    const rootExtra = {};
    const rootKeys = new Set();
    for (const st of [bState, lState, rs.value]) if (st) for (const k of Object.keys(st)) { if (k !== 'version' && k !== 'profiles') rootKeys.add(k); }
    for (const k of rootKeys) {
        const pick = pick3('root', k, !!(bState && k in bState), bState?.[k], !!(lState && k in lState), lState?.[k], !!(rs.value && k in rs.value), rs.value?.[k], conflicts);
        if (pick.has) rootExtra[k] = pick.v;
    }
    return {
        value: Object.keys(profiles).length ? { version: ADMIN_PROFILE_STATE_VERSION, profiles, ...rootExtra } : null,
        conflicts,
        held: null,
        reason: 'merged',
    };
}

/* editWitness: caller-grounded ACTUAL edit evidence, scoped PER FIELD so a witness never
 * blesses untouched stale fields. Accepts true (whole candidate - only for a verified
 * incident-time migration vouching for the exact values) or per lane:
 *   { desktop: true | ['textPt', ...], mobile: true | [...] }
 * Only WITNESSED diverging fields may win on first upload. */
const witnessedField = (witness, lane, field) => {
    if (witness === true) return true;
    if (!isPlainObject(witness)) return false;
    const w = witness[lane];
    if (w === true) return true;
    return Array.isArray(w) && w.includes(field);
};

/* Decides what the account's server field should hold after a session observation.
 *   remote:         current server value (raw; null = genuinely absent)
 *   localCandidate: this browser's persisted local profiles (raw; may be absent or stale)
 *   localBinding / currentBinding: opaque scope tags; local is trusted only on exact match
 *   adminVerified:  caller-grounded verified admin session
 *   firstUpload:    caller-grounded: THIS local store has never uploaded to the account
 *   editWitness:    per-field actual edit evidence (above); difference-from-defaults is NOT
 *                   a witness (legacy bytes differ, intentional edits can equal defaults)
 *   defaults:       optional App default lane(s); ANNOTATES conflicts with
 *                   differsFromDefaults as a review hint - never decides anything */
export function prepareAdminProfileState({ remote = null, localCandidate = null, localBinding = null, currentBinding = null, adminVerified = false, firstUpload = false, editWitness = false, defaults = null } = {}) {
    const rs = remoteStatus(remote);
    // The App's LOCAL shape is an unversioned {desktop?, mobile?} map (adminProfiles.current /
    // the middots-admin-layout-profiles key); a VERSIONED wrapper is accepted too. Any PRESENT
    // lane that fails strict cleaning makes the whole candidate corrupt - held, never trimmed.
    let localCorrupt = false; let l = null;
    if (localCandidate !== null && localCandidate !== undefined) {
        if (!isPlainObject(localCandidate)) {
            localCorrupt = true;                                                    // a nonsense root is never "empty"
        } else if ('profiles' in localCandidate || 'version' in localCandidate) {
            // Explicit versioned shape: the version is VALIDATED, never skipped. A wrong or
            // missing version, or a present-but-invalid profiles root, is corrupt - held.
            l = cleanAdminProfileState(localCandidate);
            if (l === null) localCorrupt = true;
        } else {
            // Bare App shape {desktop?, mobile?} (adminProfiles.current / the legacy key).
            // EVERY root key is validated: a pollution key or an unsupported PRESENT key is
            // not ours to trim - the whole candidate holds, raw preserved. Only a truly
            // empty map is "no local candidate".
            for (const k of Object.keys(localCandidate)) {
                if (!isSafeKey(k) || !LANES.includes(k)) { localCorrupt = true; break; }
            }
            if (!localCorrupt) {
                const profiles = {};
                for (const lane of LANES) {
                    if (!(lane in localCandidate) || localCandidate[lane] === null || localCandidate[lane] === undefined) continue;
                    const c = cleanLane(localCandidate[lane]);
                    if (c === null) { localCorrupt = true; break; }
                    profiles[lane] = c;
                }
                if (!localCorrupt && Object.keys(profiles).length) l = { version: ADMIN_PROFILE_STATE_VERSION, profiles };
            }
        }
    }
    if (rs.status === 'corrupt') return { ...holdRemote(remote, localCandidate), applyRequiresVerifiedSession: adminVerified !== true };
    if (localCorrupt) return { ...holdLocal(localCandidate, remote), applyRequiresVerifiedSession: adminVerified !== true };
    const r = rs.value;
    const bound = adminVerified === true && typeof localBinding === 'string' && localBinding.length > 0 && localBinding === currentBinding;
    const unverified = adminVerified !== true ? { applyRequiresVerifiedSession: true } : {};

    if (!l) return { value: r, held: null, reason: r ? 'remote-only' : 'empty', conflicts: [], ...unverified };
    if (!bound) return { value: r, held: l, reason: 'local-unbound-held', conflicts: [], ...unverified };   // preserved, not associated

    // Genuine absence only: the account's first upload - existing local values WIN (block 90).
    if (rs.status === 'absent') return { value: l, held: null, reason: 'first-upload-local-wins', conflicts: [] };

    const dfl = isPlainObject(defaults) ? defaults : null;
    const hint = (lane_, f, v) => {
        if (!dfl) return undefined;
        const d = isPlainObject(dfl[lane_]) ? dfl[lane_] : dfl;
        return isPlainObject(d) && f in d ? !same(v, d[f]) : undefined;
    };
    const witness = firstUpload === true && editWitness;
    const profiles = {}; const conflicts = []; let seeded = false; let witnessWon = false;
    for (const lane_ of new Set([...Object.keys(r.profiles), ...Object.keys(l.profiles)])) {
        if (!LANES.includes(lane_)) {
            // Unknown FUTURE lane: opaque whole JSON-safe value, never trimmed. Remote is
            // preserved; a bound NEW local lane seeds; divergence keeps the approved remote
            // and records a conflict with INDEPENDENT deep copies.
            const inR = lane_ in r.profiles, inL = lane_ in l.profiles;
            if (inR && inL) {
                if (!same(l.profiles[lane_], r.profiles[lane_])) {
                    profiles[lane_] = r.profiles[lane_];
                    conflicts.push({ scope: 'profiles', field: lane_, local: deepSafe(l.profiles[lane_]).value, remote: deepSafe(r.profiles[lane_]).value });
                } else profiles[lane_] = r.profiles[lane_];
            } else if (inR) profiles[lane_] = r.profiles[lane_];
            else { profiles[lane_] = l.profiles[lane_]; seeded = true; }
            continue;
        }
        const rl = r.profiles[lane_] || {}, ll = l.profiles[lane_] || {};
        const out = { ...rl };
        for (const [f, v] of Object.entries(ll)) {
            if (!(f in rl)) { out[f] = v; seeded = true; }                       // verified NEW local field seeds
            else if (same(v, rl[f])) { /* no-op */ }
            else {
                const entry = { lane: lane_, field: f, local: deepSafe(v).value, remote: deepSafe(rl[f]).value };   // independent clones: no cross-branch aliasing
                const h = hint(lane_, f, v); if (h !== undefined) entry.differsFromDefaults = h;
                if (witnessedField(witness, lane_, f)) { out[f] = v; witnessWon = true; }   // ONLY witnessed fields win
                conflicts.push(entry);                                                      // both candidates preserved either way
            }
        }
        if (Object.keys(out).length) profiles[lane_] = out;
    }
    // ROOT extras (unknown top-level fields): remote's are preserved, bound NEW local extras
    // seed, divergence keeps remote and records a conflict (root extras are never
    // witness-overwritten - the witness scopes profile fields only). Unknown FUTURE lanes
    // inside profiles flow through the lane loop above as opaque preserved values.
    const rootExtra = {};
    const rootKeys = new Set();
    for (const st of [r, l]) if (st) for (const k of Object.keys(st)) { if (k !== 'version' && k !== 'profiles') rootKeys.add(k); }
    for (const k of rootKeys) {
        const inR = k in r, inL = k in l;
        if (inR && inL) {
            if (!same(l[k], r[k])) { rootExtra[k] = r[k]; conflicts.push({ scope: 'root', field: k, local: deepSafe(l[k]).value, remote: deepSafe(r[k]).value }); }
            else rootExtra[k] = r[k];
        } else if (inR) rootExtra[k] = r[k];
        else { rootExtra[k] = l[k]; seeded = true; }
    }
    return {
        value: Object.keys(profiles).length ? { version: ADMIN_PROFILE_STATE_VERSION, profiles, ...rootExtra } : null,
        held: null,
        reason: witnessWon ? 'first-upload-witnessed-local-wins' : conflicts.length ? 'divergence-remote-kept' : seeded ? 'local-additions-seeded' : 'remote-kept',
        conflicts,
    };
}
