/* Account binding for the local state copy (STATE_KEY / 'middots-state').
 * Card 20261024-001: the full library payload persisted on this browser was applied to ANY
 * later session. After an account was wiped, every path that leaves the copy behind - a wipe
 * done on another device (the 401 containment deliberately keeps local data), a tab closed
 * before wipeDevice's delayed reset, an unknown wipe outcome - left the deleted account's
 * pieces readable by the next session here, and a different account joining both saw them and
 * merged/uploaded them into its own account.
 * The payload now carries the writing profile's scope (a sha256 of its token, never the token)
 * and is applied only under a matching scope. Precedent: the recovery store's r2 privacy gate
 * in sync.js ("another profile's records stay stored, unseen, untouched"). */
const LABEL = 'middots-state-scope:v1:';
const cache = { token: null, scope: null };

/* The profile scope for a sync token: a keyed hash, never the token itself. null when the
 * page is not joined (the anonymous device library). */
export async function scopeForToken(token) {
    if (!token) return null;
    if (cache.token === token) return cache.scope;
    try {
        const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(LABEL + token));
        const scope = [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
        cache.token = token;
        cache.scope = scope;
        return scope;
    } catch {
        return null; // hashing unavailable: fail toward the anonymous rules, never toward a match
    }
}

/* The resolved scope for exactly this token, synchronously. null when unresolved or for a
 * different token: reads then follow the anonymous rules (an anonymous copy still applies,
 * another profile's copy never does). */
export function cachedScope(token) {
    return token && cache.token === token ? cache.scope : null;
}

export function packState(scope, state) {
    return JSON.stringify({ v: 1, scope, state });
}

/* Decide what a stored payload may do for the session holding `scope` (null = not joined).
 * Returns { apply: true, stateText } or { apply: false, reason }.
 * - own copy (scope match, null included): applied
 * - anonymous copy (stored scope null) under a joined session: the designed first-join import
 * - another profile's copy: never applied, left stored and unseen (wipe residue)
 * - legacy payload (no envelope): applied only to an anonymous session. Under any joined
 *   session it stays unseen - it cannot be told apart from a wiped profile's residue. */
export function readScopedState(raw, scope) {
    if (!raw) return { apply: false, reason: 'empty' };
    let parsed;
    try { parsed = JSON.parse(raw); } catch { return { apply: false, reason: 'malformed' }; }
    if (parsed && parsed.v === 1 && parsed.state !== undefined && (typeof parsed.scope === 'string' || parsed.scope === null)) {
        if (parsed.scope === null || parsed.scope === scope) return { apply: true, stateText: JSON.stringify(parsed.state) };
        return { apply: false, reason: 'scope-mismatch' };
    }
    if (scope === null) return { apply: true, stateText: raw }; // legacy anonymous library
    return { apply: false, reason: 'legacy-under-account' };
}
