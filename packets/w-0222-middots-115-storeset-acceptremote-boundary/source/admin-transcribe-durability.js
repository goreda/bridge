// Insertion-specific durability ledger. No DOM-applied or generic HTTP success is a receipt.
// Tickets are private object capabilities, bound to an exact submitted payload and latest event.
export function createDurabilityLedger({ scope = () => '', identity = () => 'unit-identity', onUnavailable = () => {} } = {}) {
    const placements = new Map(), tickets = new WeakMap();
    let serial = 0;
    const currentIdentity = () => { try { return identity(); } catch { return null; } };
    const currentScope = () => { try { const value = scope(); return typeof value === 'string' && value.trim() && !['local-device', 'storage-unavailable'].includes(value) ? value : null; } catch { return null; } };
    const targetVersion = (payload, p) => {
        const piece = payload?.pieces?.find(x => x.id === p.pieceId);
        const version = piece?.versions?.[piece.current];
        return version?.vid === p.versionId ? version : null;
    };
    const exactLines = (payload, p) => {
        const v = targetVersion(payload, p);
        return !!v && JSON.stringify(v.lines) === JSON.stringify(p.lines);
    };
    function preserve({ id, eventId, generation, pieceId, versionId, lines, finalText, recovery, scope: insertionScope, continuity }) {
        const eligible = !!(id && eventId && Number.isSafeInteger(generation) && pieceId && versionId && Array.isArray(lines));
        const p = { id, eventId, generation, pieceId, versionId, lines: Array.isArray(lines) ? [...lines] : [], finalText, scope: insertionScope ?? currentScope(), authIdentity: continuity ? continuity.identity : currentIdentity(), eligible, serial: ++serial, recovery, pending: true };
        p.eligible = p.eligible && !!p.scope && p.scope === currentScope() && !!p.authIdentity && p.authIdentity === currentIdentity();
        placements.set(id, p);
        const metadata = { eventId, generation, pieceId, versionId, lines: p.lines, scope: p.scope, phase: 'placed-pending-confirmation' };
        const held = recovery?.heldChecked?.(id, finalText, { placement: metadata });
        p.recoverySafe = held === true;
        if (!p.recoverySafe || !eligible) onUnavailable(p);
        return { ok: p.recoverySafe && eligible, reason: p.recoverySafe ? '' : 'recovery-unavailable' };
    }
    function prepare(payload) {
        const submitted = JSON.stringify(payload), forScope = currentScope(), forIdentity = currentIdentity(), sequence = ++serial;
        const matching = [];
        for (const p of placements.values()) {
            // Every new save supersedes an older receipt for this insertion, including later deletion.
            p.latest = sequence;
            if (!forIdentity || p.authIdentity !== forIdentity || !forScope || p.scope !== forScope) p.eligible = false;
            if (p.recoverySafe && p.eligible && p.pending && p.scope === forScope && p.authIdentity === forIdentity && exactLines(payload, p)) matching.push({ p, eventId: p.eventId, generation: p.generation });
        }
        const ticket = {};
        tickets.set(ticket, { submitted, forScope, forIdentity, sequence, matching });
        return ticket;
    }
    function confirm(ticket, evidence) {
        const t = tickets.get(ticket), liveIdentity = currentIdentity(), liveScope = currentScope();
        if (!t || !t.forScope || t.forScope !== liveScope || !t.forIdentity || t.forIdentity !== liveIdentity) return 0;
        let exact = false;
        if (evidence?.kind === 'local') {
            // Caller performs the write; both original submission and immediate readback must be exact.
            if (evidence.written === t.submitted && evidence.readback === t.submitted) {
                try { exact = JSON.stringify(JSON.parse(evidence.readback)) === t.submitted; } catch { /* keep */ }
            }

        }
        if (!exact) return 0;
        let cleared = 0;
        for (const { p, eventId, generation } of t.matching) {
            if (placements.get(p.id) !== p || !p.pending || p.latest !== t.sequence || p.eventId !== eventId || p.generation !== generation) continue;
            // Checked recovery deletion must compare placement identity; it cannot delete an unrelated job.
            if (!p.recovery?.clearPlacement?.(p.id, { eventId, generation, scope: t.forScope })) continue;
            p.pending = false; placements.delete(p.id); cleared++;
        }
        tickets.delete(ticket);
        return cleared;
    }
    return { preserve, prepare, confirm, captureContext: () => ({ scope: currentScope(), identity: currentIdentity() }), scope: currentScope, pending: () => [...placements.values()].map(({ recovery, authIdentity, ...p }) => ({...p})) };
}
// Private continuity epoch. Credentials stay in this closure, never in records or diagnostics.
let observedToken = null, observedScope = null, epoch = null;
const identityObservers = new Set();
export function observeDurabilityIdentity(fn) { identityObservers.add(fn); return () => identityObservers.delete(fn); }
export function invalidateDurabilityIdentity() { observedToken = null; observedScope = null; epoch = null; for (const fn of identityObservers) { try { fn(); } catch { /* observer cannot affect identity invalidation */ } } }
function authenticatedIdentity() {
    try {
        const token = localStorage.getItem('middots-sync-token');
        const scope = localStorage.getItem('middots-sync-base-scope');
        if (!token || !scope || !scope.trim() || ['local-device', 'storage-unavailable'].includes(scope)) { invalidateDurabilityIdentity(); return null; }
        if (token !== observedToken || scope !== observedScope || !epoch) {
            observedToken = token; observedScope = scope; epoch = {};
        }
        return epoch;
    } catch { invalidateDurabilityIdentity(); return null; }
}
if (typeof window !== 'undefined') window.addEventListener('storage', event => {
    if (event.key === null || event.key === 'middots-sync-token' || event.key === 'middots-sync-base-scope') invalidateDurabilityIdentity();
});
export const durability = createDurabilityLedger({
    scope: () => localStorage.getItem('middots-sync-base-scope'),
    identity: authenticatedIdentity,
    onUnavailable: () => { try { window.dispatchEvent(new CustomEvent('middots-dictation-unsaved')); } catch { /* no DOM */ } }
});
