 */
/* L0: storage write that reports its outcome (the plain storeSet swallows failures) */
function storeSetChecked(key, value) {
    try {
        window.localStorage.setItem(key, value);
    } catch {
        return { ok: false, reason: 'write-denied' };
    }
    try {
        return window.localStorage.getItem(key) === value ? { ok: true } : { ok: false, reason: 'readback-mismatch' };
    } catch {
        return { ok: false, reason: 'readback-failed' };
    }
}
/* L0: the saved range is cloned and collapsed to its end: a dictation write never replaces a selection. */
