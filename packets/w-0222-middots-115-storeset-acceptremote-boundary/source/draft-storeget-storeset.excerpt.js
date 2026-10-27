    keys: '1980s keys',
};

/* ---- local persistence helpers -------------------------------------------
 * Best-effort localStorage wrappers; silently no-op where storage is blocked.
 */
function storeGet(key) {
    try {
        return window.localStorage.getItem(key);
    } catch {
        return null;
    }
}
function storeSet(key, value) {
    try {
        window.localStorage.setItem(key, value);
    } catch {
        /* storage unavailable in the sandboxed frame */
    }
}
/* sound fires on keydown - the earliest event a key produces */
