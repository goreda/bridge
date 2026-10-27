import { UiPresetsContext } from './ui-presets.js?v=20261027-f7-held-keys-r1';
import { readHomeLogo, writeHomeLogo } from './public-logo.js?v=20261027-f7-held-keys-r1';
import { readLiveSelection, writeButtonSet, applyButtonSet, currentButtonSet, readRingOff } from './button-set.js?v=20261027-f7-held-keys-r1';
import { AudioMigration } from './audio-migration.js?v=20261027-f7-held-keys-r1';
import { LIBRARY_PATH, DEFAULT_RANGES, RANGE_LIMITS, DEATH_NAMES, randomUnit, newPhrase, normalizeLibrary, generateLife, generateDeath, setLibrary, setHomeLogo, BETA_PHRASES, BETA_WORDS } from './logo-library.js?v=20261027-f7-held-keys-r1';
import { r as reactExports, j as jsxRuntimeExports, c as createRoot } from './vendor.js?v=20261027-f7-held-keys-r1';
import { SYNC_URL } from './pieces.js?v=20261027-f7-held-keys-r1';
import { FACES } from './faces.js?v=20261027-f7-held-keys-r1';
import { slugFor } from './uploads.js?v=20261027-f7-held-keys-r1';
import { AddPlus, PlusWord, Logo, NameField, LOGO_WORDS } from './reading.js?v=20261027-f7-held-keys-r1';
import { saveBlob, logoGifBlob } from './mailing-export.js?v=20261027-f7-held-keys-r1';
import { SRC_FILES, stashBackup, AdminPreviewFrame, Stepper, PlayButton, GlyphButton, Drop, Toggle } from './admin-shared.js?v=20261027-f7-held-keys-r1';

const ADMIN_TOKEN_KEY = 'middots-admin-token';
const adminToken = () => {
    try {
        return localStorage.getItem(ADMIN_TOKEN_KEY) ?? '';
    } catch {
        return '';
    }
};
/* every admin call rides the admin token; the page never touches the reading token */
async function adminCall(path, options = {}) {
    return fetch(`${SYNC_URL}${path}`, {
        ...options,
        headers: { Authorization: `Bearer ${adminToken()}`, ...(options.headers ?? {}) },
    });
}

function AdminPage({ faces = [], go, session = 0, onDenied }) {
    /* the token follows the parent's verification: `session` ticks every time the parent has settled the
       admin token (stored or removed), so a mount that came before the token never stays blank */
    const [tok, setTok] = reactExports.useState(adminToken());
    const [denied, setDenied] = reactExports.useState(false);
    const retried = reactExports.useRef(false);
    reactExports.useEffect(() => { setTok(adminToken()); }, [session]);
    const [stage, setStage] = reactExports.useState(null); // staged entries, newest first
    const [live, setLive] = reactExports.useState(null); // {published, fonts, full}
    const [shelf, setShelf] = reactExports.useState(null); // the working shelf: manifest order, staged-new on top, repo floor until the first full publish

    /* a refresh keeps the order he left the draft in and the repo faces he struck from it */
    const buildShelf = (staged, liveObj, prev) => {
        const rows = [];
        const seen = new Set();
        const stageSlugs = new Set(staged.map((f) => f.slug));
        if (liveObj.full)
            for (const f of liveObj.fonts) {
                seen.add(f.slug);
                rows.push({
                    ...f,
                    repo: !f.slug.startsWith('upload-'),
                    kind: f.kind ?? FACES.find((x) => x.slug === f.slug)?.kind,
                    gone: f.slug.startsWith('upload-') && !stageSlugs.has(f.slug),
                });
            }
        const fresh = [];
        for (const f of staged)
            if (!seen.has(f.slug)) {
                seen.add(f.slug);
                fresh.push({ ...f, isNew: true });
            }
        if (!liveObj.full) {
            for (const f of FACES)
                if (!seen.has(f.slug)) {
                    seen.add(f.slug);
                    rows.push({ slug: f.slug, name: f.name, kind: f.kind, repo: true });
                }
            for (const f of liveObj.fonts)
                if (!seen.has(f.slug)) {
                    seen.add(f.slug);
                    rows.push({ ...f, out: true });
                }
        }
        if (!prev) return [...fresh, ...rows];
        const rank = new Map(prev.map((f, i) => [f.slug, i]));
        const dropped = new Set(prev.filter((f) => f.dropped).map((f) => f.slug));
        return [...fresh, ...[...rows].sort((a, b) => (rank.get(a.slug) ?? 1e9) - (rank.get(b.slug) ?? 1e9))].map((f) =>
            rank.has(f.slug) ? { ...f, kind: f.kind ?? prev[rank.get(f.slug)].kind, dropped: dropped.has(f.slug) } : f
        );
    };
    const [busy, setBusy] = reactExports.useState(false);
    const [note, setNote] = reactExports.useState('');
    const fileRef = reactExports.useRef(null);
    const [kind, setKind] = reactExports.useState(() => { try { return sessionStorage.getItem('middots-admin-kind') || 'all'; } catch { return 'all'; } });
    const refresh = async () => {
        const s = await adminCall('/fonts');
        if (s.status === 401) {
            try { localStorage.removeItem(ADMIN_TOKEN_KEY); } catch { }
            setTok('');
            setDenied(true);
            // ask the parent to verify once more; a refusal after that stays visible, no loop
            if (!retried.current) { retried.current = true; onDenied?.(); }
            return;
        }
        retried.current = false; setDenied(false);
        const staged = (await s.json()).fonts ?? [];
        setStage(staged);
        const l = await fetch(`${SYNC_URL}/public/fonts`, { cache: 'no-store' });
        const lj = l.ok ? await l.json() : { published: 0, fonts: [] };
        const liveObj = { published: lj.published ?? 0, fonts: Array.isArray(lj.fonts) ? lj.fonts : [], full: !!lj.full };
        setLive(liveObj);
        setShelf((prev) => {
            const rows = buildShelf(staged, liveObj, prev);
            let edits = {}; try { edits = JSON.parse(localStorage.getItem('middots-admin-kinds') || '{}'); } catch {}
            return rows.map(f => ({ ...f, kind: edits[f.slug] ?? f.kind ?? 'other' }));
        });
    };
    reactExports.useEffect(() => {
        if (tok) void refresh();
    }, [tok]);

    const upload = async (file, selectedKind = kind) => {
        const f = slugFor(file.name);
        setBusy(true);
        setNote('');
        try {
            const chosen = selectedKind === 'all' ? null : selectedKind;
            if (!chosen) { setNote('choose a font type before uploading'); return; }
            const r = await adminCall(`/fonts/${f.slug}?name=${encodeURIComponent(f.name)}&file=${encodeURIComponent(f.file)}`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/octet-stream' },
                body: file,
            });
            if (!r.ok) { setNote(r.status === 413 ? 'fonts are 1 byte to 10 MB' : 'the upload failed'); return; }
            setNote(`${f.name} staged`);
            try { const edits = JSON.parse(localStorage.getItem('middots-admin-kinds') || '{}'); edits[f.slug] = chosen; localStorage.setItem('middots-admin-kinds', JSON.stringify(edits)); } catch {}
            await refresh();
        } finally {
            setBusy(false);
        }
    };

    reactExports.useEffect(() => {
        const pending = window.__adminPendingFont;
        if (pending) {
            delete window.__adminPendingFont;
            void upload(pending.file, pending.kind);
        }
    }, []);

    /* a repo face leaves the draft on click and the shelf on publish; an upload's bytes go now */
    const remove = async (f) => {
        if (f.repo) {
            setShelf((s) => (s ?? []).map((r) => (r.slug === f.slug ? { ...r, dropped: true } : r)));
            return;
        }
        setBusy(true);
        try {
            await adminCall(`/fonts/${f.slug}`, { method: 'DELETE' });
            await refresh();
        } finally {
            setBusy(false);
        }
    };

    /* order is his too - nudge a face up or down; publish carries the new shelf order */
    const move = (slug, dir) => {
        setShelf((s) => {
            const i = (s ?? []).findIndex((f) => f.slug === slug);
            const shown = (s ?? []).map((f, n) => ({ f, n })).filter(({ f }) => kind === 'all' || f.kind === kind);
            const at = shown.findIndex(({ f }) => f.slug === slug);
            if (at < 0) return s;
            const j = shown[at + dir]?.n ?? -1;
            if (!s || i < 0 || j < 0 || j >= s.length) return s;
            const next = [...s];
            [next[i], next[j]] = [next[j], next[i]];
            return next;
        });
    };

    const publish = async () => {
        setBusy(true);
        setNote('');
        try {
            const doc = (shelf ?? [])
                .filter((f) => !f.dropped && !f.gone && !f.out)
                .map((f) => ({ slug: f.slug, name: f.name, file: f.file, kind: f.kind }));
            const r = await adminCall('/publish', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ slot: 'fonts', doc }),
            });
            if (!r.ok) { setNote('the publish failed - nothing moved'); return; }
            const checked = await fetch(`${SYNC_URL}/public/fonts`, { cache: 'no-store' });
            const liveNow = checked.ok ? await checked.json().catch(() => null) : null;
            const matches = liveNow?.full === true && Array.isArray(liveNow.fonts) &&
                liveNow.fonts.length === doc.length && liveNow.fonts.every((f, i) =>
                    f.slug === doc[i].slug && f.name === doc[i].name &&
                    (f.file ?? '') === (doc[i].file ?? '') && (f.kind ?? null) === (doc[i].kind ?? null));
            const changed = Number.isFinite(liveNow?.published) && Number.isFinite(live?.published) && liveNow.published !== live.published;
            if (!matches || !changed) { setNote('publish not verified - public shelf or revision unchanged; draft kept'); return; }
            setNote('published - the public shelf matches the draft');
            try { localStorage.removeItem('middots-admin-kinds'); } catch {}
            await refresh();
        } finally {
            setBusy(false);
        }
    };

    const rollback = async () => {
        setBusy(true);
        setNote('');
        try {
            const before = await fetch(`${SYNC_URL}/public/fonts`, { cache: 'no-store' });
            const old = before.ok ? await before.json().catch(() => null) : null;
            if (!old || !Array.isArray(old.fonts)) { setNote('cannot verify the public shelf; rollback not sent'); return; }
            const r = await adminCall('/rollback', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ slot: 'fonts' }),
            });
            if (!r.ok) { setNote('nothing to roll back to'); return; }
            const after = await fetch(`${SYNC_URL}/public/fonts`, { cache: 'no-store' });
            const next = after.ok ? await after.json().catch(() => null) : null;
            if (!next || !Array.isArray(next.fonts) ||
                (!Number.isFinite(next.published) || next.published === old.published) &&
                JSON.stringify({ full: next.full, fonts: next.fonts }) === JSON.stringify({ full: old.full, fonts: old.fonts })) {
                setNote('rollback not verified - public shelf unchanged; check before retrying'); return;
            }
            setNote('rolled back - public shelf changed');
            await refresh();
        } finally {
            setBusy(false);
        }
    };


    if (!tok) return denied ? jsxRuntimeExports.jsx('p', { className: 'admin-note', children: 'the admin door did not open - join again to continue' }) : null;

    const liveSlugs = new Set((live?.fonts ?? []).map((f) => f.slug));
    const docRows = (shelf ?? []).filter((f) => !f.dropped && !f.gone && !f.out);
    const docSlugs = new Set(docRows.map((f) => f.slug));
    /* dirty while the draft differs from the live shelf: the first full publish, a struck face,
       a new upload, a reorder - anything publish would carry */
    const dirty =
        shelf !== null &&
        live !== null &&
        (!live.full ||
            shelf.some((f) => f.dropped || f.isNew || f.gone || f.out) ||
            docRows.length !== live.fonts.length ||
            live.fonts.some((f, i) => docRows[i]?.slug !== f.slug || docRows[i]?.kind !== (f.kind ?? FACES.find(x => x.slug === f.slug)?.kind)));
    /* faces he reads in now that a publish would orphan (door faces only - repo faces always resolve) */
    const orphans = faces.filter((u) => u && u.startsWith('upload-') && liveSlugs.has(u) && !docSlugs.has(u));
    const changeKind = async (f, k) => {
        setShelf(rows => rows.map(row => row.slug === f.slug ? { ...row, kind: k } : row));
        try { const edits = JSON.parse(localStorage.getItem('middots-admin-kinds') || '{}'); edits[f.slug] = k; localStorage.setItem('middots-admin-kinds', JSON.stringify(edits)); } catch {}
    };

    return jsxRuntimeExports.jsxs('div', {
        className: 'admin-page shelf-page',
        children: [
            jsxRuntimeExports.jsx('div', {
                className: 'logo-slot',
                children: jsxRuntimeExports.jsx(Logo, { admin: true }),
            }),
            jsxRuntimeExports.jsx(AdminTitles, { go, on: 'admin', stage, live, shelf, kind, setKind, upload, fileRef }),
            jsxRuntimeExports.jsxs('div', {
                className: 'story editor-story open',
                children: [
                    jsxRuntimeExports.jsxs('div', { className: 'admin-shelf-meta', children: [
                        jsxRuntimeExports.jsx('span', { className: 'admin-meta-number', children: String(stage?.length ?? '··').padStart(2, '0') }),
                        jsxRuntimeExports.jsx('span', { className: 'admin-meta-name', children: String(live?.fonts?.length ?? '··').padStart(2, '0') }),
                        jsxRuntimeExports.jsx('input', { ref: fileRef, type: 'file', accept: '.ttf,.otf,.woff,.woff2', hidden: true,
                            onChange: e => { const f = e.target.files?.[0]; e.target.value = ''; if (f) void upload(f); } }),
                    ] }),
                    jsxRuntimeExports.jsx('div', {
                        className: 'story-fold editor-fold',
                        children: jsxRuntimeExports.jsxs('div', {
                            className: 'story-body editor-body',
                            children: [
            (shelf ?? []).filter(f => kind === 'all' || f.kind === kind).map((f) => {
                const i = (shelf ?? []).findIndex(row => row.slug === f.slug);
                const leaving = f.dropped || f.gone || f.out;
                return jsxRuntimeExports.jsxs('div', { id: `face-${f.slug}`,
                    className: `admin-row${f.isNew ? ' admin-row-new' : ''}${leaving ? ' admin-row-out' : ''}`,
                    children: [
                        jsxRuntimeExports.jsx('span', { className: 'admin-face-number', children: String(i + 1).padStart(2, '0') }),
                        jsxRuntimeExports.jsx('span', { className: 'admin-face-name', children: f.name }),
                        jsxRuntimeExports.jsx(KindPick, { value: f.kind || 'other', disabled: busy || leaving,
                            label: `${f.name} font type`, onPick: (k) => void changeKind(f, k) }),
                        !leaving && jsxRuntimeExports.jsx('button', { className: 'admin-move', disabled: busy || (kind === 'all' ? i === 0 : (shelf ?? []).filter(x => x.kind === kind)[0]?.slug === f.slug),
                            onClick: () => move(f.slug, -1), children: '↑' }),
                        !leaving && jsxRuntimeExports.jsx('button', { className: 'admin-move', disabled: busy || (kind === 'all' ? i === (shelf?.length ?? 0) - 1 : (shelf ?? []).filter(x => x.kind === kind).at(-1)?.slug === f.slug),
                            onClick: () => move(f.slug, 1), children: '↓' }),
                        !leaving && jsxRuntimeExports.jsx('button', { className: 'admin-face-del', disabled: busy,
                            onClick: () => void remove(f), children: '×' }),
                    ],
                }, f.slug);
            }),
            orphans.length > 0 &&
                jsxRuntimeExports.jsx('p', {
                    className: 'admin-warn',
                    children: `set in your pieces but not staged: ${orphans.join(', ')} - they fall back to a default face`,
                }),
            jsxRuntimeExports.jsx('div', {
                className: 'admin-row admin-row-publish',
                children: jsxRuntimeExports.jsx('button', {
                    className: 'admin-rollback',
                    disabled: busy,
                    onClick: () => void rollback(),
                    children: 'roll back',
                }),
            }),
            note && jsxRuntimeExports.jsx('p', { className: 'admin-note', children: note }),
                            ],
                        }),
                    }),
                ],
            }),
            jsxRuntimeExports.jsxs(AdminRings, {
                children: [
                    jsxRuntimeExports.jsx('span', { className: 'admin-ring-gap' }),
                    ringBtn(busy ? 'publishing' : dirty ? 'publish' : 'nothing to publish', trayArrow(true), busy || !dirty, () => void publish()),
                ],
            }),
        ],
    });
}


/* One title column across the admin rooms: the public piece/date hierarchy, not tabs. */
const ADMIN_KINDS = ['all', 'sans', 'serif', 'mono', 'script', 'variable', 'other'];
function KindPick({ value, disabled, onPick, label }) {
    const [open, setOpen] = reactExports.useState(false);
    reactExports.useEffect(() => {
        if (!open) return undefined;
        const onDoc = (e) => { if (!e.target.closest('.admin-kindpick')) setOpen(false); };
        const onKey = (e) => { if (e.key === 'Escape') setOpen(false); };
        document.addEventListener('mousedown', onDoc);
        document.addEventListener('keydown', onKey);
        return () => { document.removeEventListener('mousedown', onDoc); document.removeEventListener('keydown', onKey); };
    }, [open]);
    return jsxRuntimeExports.jsxs('span', { className: `admin-kindpick${open ? ' open' : ''}`, children: [
        jsxRuntimeExports.jsx('button', { type: 'button', className: 'admin-kindpick-btn',
            'aria-label': label, 'aria-expanded': open, disabled, onClick: () => setOpen(!open), children: value }),
        open && jsxRuntimeExports.jsx('span', { className: 'admin-kindpick-list', children:
            ADMIN_KINDS.filter((k) => k !== 'all').map((k) => jsxRuntimeExports.jsx('button', {
                type: 'button', className: `admin-kindpick-one${k === value ? ' on' : ''}`,
                onClick: () => { setOpen(false); if (k !== value) onPick(k); }, children: k,
            }, k)),
        }),
    ] });
}
/* the mailing engine's own repo (goreda/middots-mail), not part of the EDITABLE allowlist */
/* The code list in groups by kind - js, json, html, css, the rest - each alphabetical,
   one empty line between groups and no labels. */
const CODE_GROUPS = [/\.(m?js)$/i, /\.json$/i, /\.html?$/i, /\.css$/i];
function groupCodeFiles(files) {
    const groups = [...CODE_GROUPS, null].map(() => []);
    for (const f of files) {
        const i = CODE_GROUPS.findIndex(re => re.test(f.path));
        groups[i < 0 ? CODE_GROUPS.length : i].push(f);
    }
    return groups.filter(g => g.length).map(g => g.sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
}
const MAILING_FILES = ['preview', 'copy', 'layout', 'logo', 'icons', 'frame'];
const ADMIN_FOLD_KEY = 'middots-admin-folds';
function adminFoldState() {
    try { return { shelf: true, code: true, changes: false, history: false, ...JSON.parse(localStorage.getItem(ADMIN_FOLD_KEY) || '{}') }; }
    catch { return { shelf: true, code: true, changes: false, history: false }; }
}
/* The titles are mounted by every admin page, so state kept inside the component is rebuilt on
 * each route change: folds re-read storage, every list refetched and empty until it lands.
 * Folds and lists live at module level instead; navigation never touches a fold. */
const foldListeners = new Set();
let foldStore = null;
const foldGet = () => (foldStore ??= adminFoldState());
const foldSet = (id, open) => {
    foldStore = { ...foldGet(), [id]: open };
    try { localStorage.setItem(ADMIN_FOLD_KEY, JSON.stringify(foldStore)); } catch { }
    foldListeners.forEach(f => f());
};
const foldSubscribe = (f) => { foldListeners.add(f); return () => foldListeners.delete(f); };
const titleCache = { tree: [], drafts: [], vers: [], counts: { staged: null, live: null }, typeCounts: null };
/* ---- the admin plus ---------------------------------------------------------
 * The reader's add plus (reading.js AddPlus, same strokes, same horizon seat, same blink), on the
 * left of every admin page. One plus, one meaning: add one of what this section holds. A section
 * that holds nothing to add (changes, history, the audio migration room) keeps the horizontal
 * stroke alone - no vertical, no action, no blink (his ruling, 1 Oct 20:52). ADMIN_PLUS flips a page. */
const ADMIN_PLUS = { admin: 'plus', 'admin/logo': 'plus', 'admin/mailing': 'plus', 'admin/edit': 'plus', 'admin/changes': 'dash', 'admin/history': 'dash', 'admin/audio': 'dash' };
const NEW_FILE_NAME = /^[a-z0-9][a-z0-9-]{0,48}\.(js|css|json|md)$/; /* the worker's own rule, repeated so a wrong name never leaves the page */
const ADMIN_PLUS_LABEL = { admin: 'add a font', 'admin/logo': 'add a phrase', 'admin/mailing': 'add a copy', 'admin/edit': 'add a file' };
/* the word the plus is for, typed upward from the top of the plus while it is hovered or focused
   (owner request relayed 1 Oct 21:03): one steady rhythm, letter by letter, then quickly taken back on leave.
   House rule (21:16): every typewriter has a blinking caret at its typing head. Here it is a thin crimson
   bar standing on the baseline after the last letter; it blinks slowly while the plus is hovered or
   focused, stays blinking after the word is complete, and goes with the last letter on leave.
   Reduced motion shows the whole word at once. The aria-label stays the accessible name. */
const ADMIN_PLUS_WORD = { admin: 'font', 'admin/logo': 'phrase', 'admin/edit': 'file', 'admin/mailing': 'copy' };

function AdminPlus({ on, fileRef }) {
    const kind = ADMIN_PLUS[on];
    const [naming, setNaming] = reactExports.useState(false);
    const [problem, setProblem] = reactExports.useState('');
    const [awake, setAwake] = reactExports.useState(false);
    if (kind === 'dash') return jsxRuntimeExports.jsx('div', { className: 'hair-plus hair-dash', 'aria-hidden': 'true' });
    if (kind !== 'plus') return null;
    if (on === 'admin/edit' && naming) return jsxRuntimeExports.jsxs('div', { className: 'admin-plus-name', children: [
        jsxRuntimeExports.jsx(NameField, { initial: '', label: 'file name', onDone: (name) => {
            setNaming(false);
            if (!name) { setProblem(''); return; }
            if (!NEW_FILE_NAME.test(name)) { setProblem('lowercase letters, digits and hyphens, then .js .css .json or .md'); return; }
            setProblem('');
            window.dispatchEvent(new CustomEvent('admin-new-file', { detail: name }));
        } }),
    ] });
    const add = () => {
        if (on === 'admin/edit') { setProblem(''); setNaming(true); }
        else if (on === 'admin') fileRef?.current?.click();
        else if (on === 'admin/logo') document.querySelector('.logo-phrase-add .logo-phrase-text')?.focus();
        else window.dispatchEvent(new CustomEvent('admin-plus', { detail: on }));
    };
    return jsxRuntimeExports.jsxs('div', { className: 'hair-plus-seat', onPointerEnter: () => setAwake(true), onPointerLeave: () => setAwake(false), onFocus: () => setAwake(true), onBlur: () => setAwake(false), children: [
        jsxRuntimeExports.jsx(AddPlus, { label: ADMIN_PLUS_LABEL[on], onClick: add }),
        jsxRuntimeExports.jsx(PlusWord, { word: ADMIN_PLUS_WORD[on], awake }),
        problem && jsxRuntimeExports.jsx('p', { className: 'admin-note admin-plus-note', children: problem }),
    ] });
}
// Unit-snapped scroll shared by scroll columns: a unit is fully visible or fully gone. The box
// height is quantised to a unit boundary, scrollTop always rests on a unit top, and one wheel
// notch (or one settled touch drag) moves exactly one unit, animated.
function unitSnapColumn(el, unitSelector, availFn) {
    const units = () => [...el.querySelectorAll(unitSelector)].filter(u => {
        const box = u.closest('.admin-children');
        return u.getBoundingClientRect().height > 0.5 && (!box || box.getBoundingClientRect().height > 0.5);
    });
    const geom = () => {
        const e0 = el.getBoundingClientRect().top - el.scrollTop;
        const k = units(), top = k.map(u => u.getBoundingClientRect().top - e0), bot = k.map(u => u.getBoundingClientRect().bottom - e0);
        return { k, top, bot };
    };
    const fit = (start) => {
        const { top, bot } = geom(); const last = top.length - 1;
        if (last < 0) return null;
        const avail = availFn();
        let sMax = 0; while (sMax < last && bot[last] - top[sMax] > avail) sMax++;
        const s = Math.max(0, Math.min(start, sMax));
        let j = s; while (j < last && bot[j + 1] - top[s] <= avail) j++;
        return { s, j, sMax, top, bot, height: bot[j] - top[s] };
    };
    const index = () => { const { top } = geom(); let b = 0; top.forEach((t, i) => { if (Math.abs(t - el.scrollTop) < Math.abs(top[b] - el.scrollTop)) b = i; }); return b; };
    const quantise = () => {
        if (getComputedStyle(el).overflowY === 'visible') { el.style.maxHeight = ''; return; }
        const f = fit(index()); if (!f) return;
        const total = f.bot[f.bot.length - 1] - f.top[0];
        if (total <= availFn() + 0.5) { el.style.maxHeight = ''; el.scrollTop = 0; return; }
        el.style.maxHeight = `${f.height}px`;
        if (Math.abs(el.scrollTop - f.top[f.s]) > 0.5 && !el.__moving) el.scrollTop = f.top[f.s];
    };
    const step = (dir, n = 1) => {
        const f = fit(index() + dir * n); if (!f) return;
        el.__moving = true; el.style.maxHeight = `${f.height}px`;
        el.scrollTo({ top: f.top[f.s], behavior: 'smooth' });
        clearTimeout(el.__mt); el.__mt = setTimeout(() => { el.__moving = false; quantise(); }, 320);
    };
    let acc = 0, lock = 0;
    const wheel = e => {
        if (getComputedStyle(el).overflowY === 'visible') return;
        e.preventDefault();
        const now = performance.now(); if (now < lock) return;
        acc += e.deltaY; if (Math.abs(acc) < 30) return;
        const dir = acc > 0 ? 1 : -1; const n = Math.min(4, Math.max(1, Math.round(Math.abs(acc) / 33))); acc = 0; lock = now + 60; step(dir, n);
    };
    let settle; const onScroll = () => { if (el.__moving) return; clearTimeout(settle); settle = setTimeout(() => { const f = fit(index()); if (f) { el.__moving = true; el.scrollTo({ top: f.top[f.s], behavior: 'smooth' }); clearTimeout(el.__mt); el.__mt = setTimeout(() => { el.__moving = false; quantise(); }, 320); } }, 110); };
    el.addEventListener('wheel', wheel, { passive: false });
    el.addEventListener('scroll', onScroll);
    quantise();
    return { quantise, off: () => { el.removeEventListener('wheel', wheel); el.removeEventListener('scroll', onScroll); clearTimeout(settle); clearTimeout(el.__mt); } };
}
function AdminTitles({ go, on, files, rows, stage, live, shelf, kind, setKind, upload, fileRef, current, setCurrent, vers }) {
    const titlesRef = reactExports.useRef(null);
    // The first row's baseline offset below the column's top, measured for the live face, size
    // and line height, so the baseline lands on the horizon whatever the index face is.
    reactExports.useLayoutEffect(() => {
        const el = titlesRef.current;
        if (!el) return;
        const measure = () => {
            const label = el.querySelector('.admin-section-title');
            if (!label) return;
            const probe = document.createElement('span');
            probe.style.cssText = 'display:inline-block;width:0;height:0;vertical-align:baseline';
            label.appendChild(probe);
            const base = probe.getBoundingClientRect().bottom - el.getBoundingClientRect().top;
            probe.remove();
            if (Number.isFinite(base) && base > 0) el.style.setProperty('--admin-index-base', `${base.toFixed(3)}px`);
        };
        measure();
        document.fonts?.addEventListener?.('loadingdone', measure);
        document.fonts?.ready?.then(measure);
        window.addEventListener('resize', measure);
        const watch = typeof ResizeObserver === 'function' ? new ResizeObserver(measure) : null;
        watch?.observe(el.querySelector('.admin-head-row') ?? el);
        return () => { document.fonts?.removeEventListener?.('loadingdone', measure); window.removeEventListener('resize', measure); watch?.disconnect(); };
    });
    const legacyFolds = reactExports.useSyncExternalStore(foldSubscribe, foldGet);
    const presets = reactExports.useContext(UiPresetsContext);
    const folds = presets ? { shelf: true, code: true, changes: false, history: false, ...presets.uiPresets.admin.folds } : legacyFolds;
    const setSectionFold = (id, flag) => {
        if (!presets) { foldSet(id, flag); return; }
        presets.setUiPresets(previous => ({ ...previous, admin: { ...previous.admin, folds: { ...previous.admin.folds, [id]: flag } } }));
    };
    const [activeKind, setActiveKind] = reactExports.useState(() => { try { return sessionStorage.getItem('middots-admin-kind') || 'all'; } catch { return 'all'; } });
    const [tree, setTree] = reactExports.useState(titleCache.tree);
    const [drafts, setDrafts] = reactExports.useState(titleCache.drafts);
    const [versLocal, setVersLocal] = reactExports.useState(titleCache.vers);
    const [chosenFile, setChosenFile] = reactExports.useState(() => { try { return sessionStorage.getItem('middots-admin-file') || 'app.js'; } catch { return 'app.js'; } });
    const [counts, setCounts] = reactExports.useState(titleCache.counts);
    const [typeCounts, setTypeCounts] = reactExports.useState(titleCache.typeCounts);
    const [chosenMailing, setChosenMailing] = reactExports.useState(() => { try { return sessionStorage.getItem('middots-admin-mailing-file') || 'preview'; } catch { return 'copy'; } });
    const anyFileRef = reactExports.useRef(null);
    if (files !== undefined) titleCache.tree = files;
    if (rows !== undefined) titleCache.drafts = rows;
    if (vers !== undefined) titleCache.vers = vers;
    reactExports.useEffect(() => {
        if (files === undefined) adminCall('/repo/tree').then(r => r.ok ? r.json() : {}).then(j => { titleCache.tree = j.files || []; setTree(titleCache.tree); }).catch(() => {});
        if (rows === undefined) adminCall('/repo/drafts').then(r => r.ok ? r.json() : {}).then(j => { titleCache.drafts = j.drafts || []; setDrafts(titleCache.drafts); }).catch(() => {});
        if (vers === undefined) adminCall('/repo/commits?per_page=12').then(r => r.ok ? r.json() : []).then(j => { titleCache.vers = Array.isArray(j) ? j : []; setVersLocal(titleCache.vers); }).catch(() => {});
        if (stage === undefined) Promise.all([adminCall('/fonts'), fetch(`${SYNC_URL}/public/fonts`, { cache: 'no-store' })])
            .then(async ([a,b]) => {
                const staged = a.ok ? (await a.json()).fonts ?? [] : [];
                const published = b.ok ? (await b.json()) : { fonts: [] };
                titleCache.counts = { staged: staged.length, live: published.fonts?.length ?? 0 }; setCounts(titleCache.counts);
                const edits = (() => { try { return JSON.parse(localStorage.getItem('middots-admin-kinds') || '{}'); } catch { return {}; } })();
                const bySlug = new Map(published.full ? [] : FACES.map(f => [f.slug, f]));
                for (const f of published.fonts ?? []) bySlug.set(f.slug, f);
                for (const f of staged) bySlug.set(f.slug, f);
                const tally = {};
                for (const f of bySlug.values()) tally[edits[f.slug] ?? f.kind ?? 'other'] = (tally[edits[f.slug] ?? f.kind ?? 'other'] ?? 0) + 1;
                titleCache.typeCounts = tally; setTypeCounts(tally);
            }).catch(() => {});
    }, [on]);
    const sections = [
        ['shelf', 'shelf', 'admin'], ['logo', 'logo', 'admin/logo'], ['code', 'code', 'admin/edit'], ['mailing', 'mailing', 'admin/mailing'],
        ['changes', 'changes', 'admin/changes'], ['history', 'history', 'admin/history'],
    ];
    // The marker owns folding; the text owns navigation. Neither changes the other.
    const toggleSection = (id) => setSectionFold(id, !folds[id]);
    const chooseFile = (path) => {
        try { sessionStorage.setItem('middots-admin-file', path); } catch { }
        setChosenFile(path);
        if (window.matchMedia('(max-width: 700px)').matches) {
            // phone: picking a file folds the index sections and the editor lands its first line on the horizon
            try { sessionStorage.setItem('middots-admin-pick', path); } catch { }
            for (const [id] of sections) if (folds[id]) setSectionFold(id, false);
        }
        if (on === 'admin/edit') setCurrent?.(path);
        else go('admin/edit');
    };
    const chooseKind = (k) => {
        try { sessionStorage.setItem('middots-admin-kind', k); } catch { }
        setActiveKind(k);
        if (on === 'admin') setKind?.(k);
        else go('admin');
    };
    const visibleFaces = shelf?.filter(f => !f.dropped && !f.gone && !f.out);
    reactExports.useLayoutEffect(() => {
        const el = titlesRef.current;
        if (!el) return;
        const avail = () => innerHeight - el.getBoundingClientRect().top;
        const col = unitSnapColumn(el, '.admin-head-row, .admin-child', avail);
        const again = () => col.quantise();
        window.addEventListener('resize', again);
        // the folds open with a 0.24s grid transition, and fonts settle after mount: measure again when they finish
        el.addEventListener('transitionend', again);
        let ticks = 0; const late = setInterval(() => { again(); if (++ticks >= 25) clearInterval(late); }, 100);
        const watch = typeof ResizeObserver === 'function' ? new ResizeObserver(again) : null;
        el.querySelectorAll('.admin-title-group, .admin-children-inner').forEach(g => watch?.observe(g));
        return () => { window.removeEventListener('resize', again); el.removeEventListener('transitionend', again); clearInterval(late); watch?.disconnect(); col.off(); };
    });
    const faceCounts = visibleFaces ? visibleFaces.reduce((acc, f) => { acc[f.kind ?? 'other'] = (acc[f.kind ?? 'other'] ?? 0) + 1; return acc; }, {}) : typeCounts;
    const countFor = k => k === 'all' ? (visibleFaces?.length ?? (faceCounts ? Object.values(faceCounts).reduce((a, b) => a + b, 0) : null)) : faceCounts?.[k] ?? (faceCounts ? 0 : null);
    const codeFiles = files ?? tree;
    const changes = rows ?? drafts;
    return jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [jsxRuntimeExports.jsx(AdminPlus, { on, fileRef }), jsxRuntimeExports.jsx('div', {
        className: 'admin-titles', ref: titlesRef,
        children: sections.map(([id, label, route]) => jsxRuntimeExports.jsxs('div', {
            className: `admin-title-group${on === route ? ' on' : ''}`,
            children: [
                jsxRuntimeExports.jsxs('div', { className: 'admin-head-row', children: [
                    id !== 'logo' ? jsxRuntimeExports.jsx('button', {
                        type: 'button', className: 'admin-title-dot admin-section-fold',
                        'aria-label': `fold ${label}`, 'aria-expanded': !!folds[id],
                        onClick: () => toggleSection(id), children: '·',
                    }) : jsxRuntimeExports.jsx('span', { className: 'admin-title-dot', 'aria-hidden': 'true', style: { visibility: 'hidden' }, children: '·' }),
                    jsxRuntimeExports.jsx('button', {
                        type: 'button', className: 'admin-section-title',
                        onClick: () => go(route), children: label,
                    }),
                ] }),
                jsxRuntimeExports.jsx('div', {
                    className: `admin-children${folds[id] ? ' open' : ''}`, inert: folds[id] ? undefined : '',
                    children: jsxRuntimeExports.jsx('div', { className: 'admin-children-inner', children: id === 'shelf' ? jsxRuntimeExports.jsx(jsxRuntimeExports.Fragment, { children:
                        ADMIN_KINDS.map(k => jsxRuntimeExports.jsx('button', { type: 'button',
                            className: `admin-child admin-kind${(kind ?? activeKind) === k ? ' on' : ''}`,
                            onClick: () => chooseKind(k), children: jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [jsxRuntimeExports.jsx('span', { children: k }), jsxRuntimeExports.jsx('span', { className: 'admin-kind-count', children: countFor(k) ?? '··' })] }) }, k)),
                    }) : id === 'code' ? groupCodeFiles(codeFiles).flatMap((group, gi) => [
                        ...(gi ? [jsxRuntimeExports.jsx('div', { className: 'admin-code-gap', 'aria-hidden': 'true' }, `gap-${gi}`)] : []),
                        ...group.map(f => jsxRuntimeExports.jsx('button', {
                            type: 'button', className: `admin-child${(current ?? chosenFile) === f.path && on === route ? ' on' : ''}`,
                            onClick: () => chooseFile(f.path), children: f.path,
                        }, f.path)),
                    ]) : id === 'changes' ? (changes.length ? changes.map(f => jsxRuntimeExports.jsx('button', {
                        type: 'button', className: 'admin-child', onClick: () => { try { sessionStorage.setItem('middots-admin-change', f.path); } catch {} if (on === 'admin/changes') window.dispatchEvent(new CustomEvent('admin-change-path', { detail: f.path })); else go('admin/changes'); }, children: f.path,
                    }, f.path)) : jsxRuntimeExports.jsx('span', { className: 'admin-child', children: 'nothing applied' }))
                    : id === 'history' ? ((vers ?? versLocal).length ? (vers ?? versLocal).slice(0, 12).map((v) => jsxRuntimeExports.jsx('button', {
                        type: 'button',
                        className: 'admin-child', onClick: () => { try { sessionStorage.setItem('middots-admin-version', v.sha); } catch {} if (on === 'admin/history') window.dispatchEvent(new CustomEvent('admin-version-sha', { detail: v.sha })); else go('admin/history'); },
                        children: `${v.sha.slice(0, 7)} · ${(v.commit?.committer?.date ?? '').slice(5, 10)}`,
                    }, v.sha)) : jsxRuntimeExports.jsx('span', { className: 'admin-child', children: 'no publishes yet' }))
                    : id === 'mailing' ? MAILING_FILES.map(f => jsxRuntimeExports.jsx('button', {
                        type: 'button', className: `admin-child${chosenMailing === f && on === route ? ' on' : ''}`,
                        onClick: () => { try { sessionStorage.setItem('middots-admin-mailing-file', f); } catch { } setChosenMailing(f); if (on === route) window.dispatchEvent(new CustomEvent('admin-mailing-file', { detail: f })); else go('admin/mailing'); }, children: f,
                    }, f))
                    : null }),
                }),
            ],
        }, id)),
    })] });
}

/* ---- the history (#/admin/history) -----------------------------------------
 * Every publish is a commit on the repo, so the page's memory is the repo's
 * own: the list and any chosen version reach it through the worker's repo door
 * (the page holds no key of its own), and "bring back" restores the editable
 * files to that commit through the same draft + publish door a hand edit takes
 * (his ruling, 28 Sep 22:21).
 */
function HistoryPage({ go }) {
    const [vers, setVers] = reactExports.useState(null); // the publish list, newest first
    const [openSha, setOpenSha] = reactExports.useState(() => { try { return sessionStorage.getItem('middots-admin-version') || ''; } catch { return ''; } });
    const [detail, setDetail] = reactExports.useState(null);
    const [busy, setBusy] = reactExports.useState(false);
    const [note, setNote] = reactExports.useState('');
    reactExports.useEffect(() => {
        const cb = (e) => setOpenSha(e.detail);
        window.addEventListener('admin-version-sha', cb);
        return () => window.removeEventListener('admin-version-sha', cb);
    }, []);
    reactExports.useEffect(() => {
        void (async () => {
            const j = await adminCall('/repo/commits?per_page=40').then((r) => (r.ok ? r.json() : null)).catch(() => null);
            setVers(Array.isArray(j) ? j : []);
            if (!Array.isArray(j)) setNote('the history did not load');
        })();
    }, []);
    reactExports.useEffect(() => {
        setDetail(null);
        if (!openSha) return;
        void (async () => {
            const j = await adminCall(`/repo/commits/${openSha}`).then((r) => (r.ok ? r.json() : null)).catch(() => null);
            setDetail(j);
        })();
    }, [openSha]);

    /* a version returns through the same door a hand edit takes: the files as they stood
       at that commit become the drafts, one publish carries them out together */
    const bringBack = async (sha) => {
        setBusy(true);
        setNote('');
        try {
            const d = await adminCall('/repo/drafts');
            const dj = d.ok ? await d.json().catch(() => null) : null;
            if (!dj || !Array.isArray(dj.drafts)) { setNote('cannot check applied changes - nothing moved'); return; }
            if (dj.drafts.length) { setNote('applied changes are waiting - publish them or let them go first'); return; }
            const [oldTree, liveTree] = await Promise.all([
                adminCall(`/repo/tree?ref=${sha}`).then((r) => r.ok ? r.json() : null).catch(() => null),
                adminCall('/repo/tree').then((r) => r.ok ? r.json() : null).catch(() => null),
            ]);
            if (!oldTree?.files || !liveTree?.sha || !liveTree?.files) { setNote('the two versions did not load - nothing moved'); return; }
            const oldFiles = new Map(oldTree.files.map((x) => [x.path, x.sha]));
            const paths = liveTree.files.filter((x) => SRC_FILES.includes(x.path) && oldFiles.has(x.path) && oldFiles.get(x.path) !== x.sha).map((x) => x.path);
            if (!paths.length) { setNote('no editable files differ from that version'); return; }
            if (paths.length > 1 && !window.confirm(`Bring back ${paths.length} files from ${sha.slice(0, 7)}? This publishes a new version.`)) return;
            const wanted = {};
            for (const p of paths) {
                const rc = await adminCall(`/repo/file?path=${encodeURIComponent(p)}&ref=${sha}`);
                if (!rc.ok) { setNote(`the old ${p} did not load - nothing moved`); return; }
                wanted[p] = (await rc.json()).content;
            }
            const freshTree = await adminCall('/repo/tree').then((r) => r.ok ? r.json() : null).catch(() => null);
            if (freshTree?.sha !== liveTree.sha) { setNote('a newer publish landed - nothing moved'); return; }
            const before = {};
            for (const p of paths) {
                const rf = await adminCall(`/repo/file?path=${encodeURIComponent(p)}`);
                if (rf.ok) before[p] = (await rf.json()).content;
            }
            for (const p of paths) {
                const put = await adminCall('/repo/draft', { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ path: p, content: wanted[p] }) });
                if (!put.ok) { setNote('the version could not be staged - nothing moved'); return; }
            }
            const r = await adminCall('/repo/publish-src', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ message: `back to ${sha.slice(0, 7)}` }) });
            const j = await r.json().catch(() => ({}));
            if (!r.ok || !j.committed) { setNote(j.error ?? 'the bring-back failed'); return; }
            stashBackup({ when: Date.now(), sha: j.sha, files: before });
            setNote(`brought back ${sha.slice(0, 7)} - the page rebuilds in a minute or two`);
        } finally {
            setBusy(false);
        }
    };

    return jsxRuntimeExports.jsxs('div', {
        className: 'admin-page history-page',
        children: [
            jsxRuntimeExports.jsx('div', { className: 'logo-slot', children: jsxRuntimeExports.jsx(Logo, { admin: true }) }),
            jsxRuntimeExports.jsx(AdminTitles, { go, on: 'admin/history', vers }),
            jsxRuntimeExports.jsxs('div', {
                className: 'story editor-story open',
                children: [
                    jsxRuntimeExports.jsx('div', {
                        className: 'story-fold editor-fold',
                        children: jsxRuntimeExports.jsxs('div', {
                            className: 'story-body editor-body',
                            children: [
                                openSha &&
                                    jsxRuntimeExports.jsxs('div', {
                                        className: 'changes-open',
                                        children: [
                                            jsxRuntimeExports.jsx('button', {
                                                className: 'admin-face-del',
                                                disabled: busy,
                                                onClick: () => void bringBack(openSha),
                                                children: busy ? 'bringing back' : 'bring back',
                                            }),
                                            jsxRuntimeExports.jsxs('div', {
                                                className: 'diff-block',
                                                children: [
                                                    jsxRuntimeExports.jsx('div', { className: 'diff-ctx', children: `${openSha.slice(0, 7)} · ${(detail?.commit?.committer?.date ?? '').slice(0, 10)}` }),
                                                    jsxRuntimeExports.jsx('div', { className: 'diff-ctx', children: (detail?.commit?.message ?? '').split('\n')[0] }),
                                                    ...(detail?.files ?? []).map((f) =>
                                                        jsxRuntimeExports.jsx('div', {
                                                            className: SRC_FILES.includes(f.filename) ? 'diff-in' : 'diff-ctx',
                                                            children: `  ${f.filename}  +${f.additions} -${f.deletions}`,
                                                        }, f.filename),
                                                    ),
                                                ],
                                            }),
                                        ],
                                    }),
                                !openSha && vers !== null && jsxRuntimeExports.jsx('p', { className: 'admin-note', children: vers.length ? 'a title on the left opens a version' : 'no publishes yet' }),
                                note && jsxRuntimeExports.jsx('p', { className: 'admin-note', children: note }),
                            ],
                        }),
                    }),
                ],
            }),
        ],
    });
}

/* the door on the right edge: from the editor to the home page, from the changes folder too -
   the preview hands one back from the same spot (the worker sets it into the page it serves) */
function SideDoor({ label }) {
    return jsxRuntimeExports.jsx('a', {
        className: 'ring-btn ring-door',
        href: '#/',
        'aria-label': label,
        'data-tip': label,
        onClick: (e) => {
            e.preventDefault(); /* home is a walk in place, not a worker round-trip */
            location.hash = '#/';
        },
        children: jsxRuntimeExports.jsx('svg', {
            width: '14',
            height: '14',
            viewBox: '0 0 14 14',
            'aria-hidden': 'true',
            children: jsxRuntimeExports.jsx('path', {
                d: 'M2.2 6.6 7 2.5l4.8 4.1M3.6 5.6v5.9h2.5V8.6h1.8v2.9h2.5V5.6',
                fill: 'none',
                stroke: 'currentColor',
                strokeWidth: '1.1',
                strokeLinejoin: 'round',
            }),
        }),
    });
}

/* the ring atom and its tray arrow, shared by every admin rail: a 34px hairline circle,
   a glyph inside, the word in the tip - the right rail's own button language */
const ringBtn = (tip, glyph, disabled, onClick) =>
    jsxRuntimeExports.jsx('button', {
        type: 'button',
        className: 'ring-btn',
        'aria-label': tip,
        'data-tip': tip,
        disabled,
        onClick,
        children: glyph,
    });
const trayArrow = (up) =>
    jsxRuntimeExports.jsxs('svg', {
        width: '14',
        height: '14',
        viewBox: '0 0 14 14',
        'aria-hidden': 'true',
        children: [
            jsxRuntimeExports.jsx('path', {
                d: up ? 'M7 9V2M4 4.8 7 1.8l3 3' : 'M7 2v7M4 6.2 7 9.2l3-3',
                fill: 'none',
                stroke: 'currentColor',
                strokeWidth: '1.1',
            }),
            jsxRuntimeExports.jsx('path', {
                d: 'M3 7.5v4h8v-4',
                fill: 'none',
                stroke: 'currentColor',
                strokeWidth: '1.1',
            }),
        ],
    });

/* the admin's rings ride the public rail: portaled into the controls stack, they ghost and
   wake with it, travel with the horizon, and sit below the page's own buttons - a fixed rail
   of their own overlapped the stack whenever the horizon moved (his ruling, 27 Sep 21:00) */
function AdminRings({ children }) {
    const slotRef = reactExports.useRef(null);
    reactExports.useEffect(() => {
        const host = document.querySelector('.controls');
        if (!host) return undefined;
        const slot = document.createElement('span');
        slot.className = 'admin-slot';
        host.appendChild(slot);
        const root = createRoot(slot);
        slotRef.current = root;
        return () => {
            slotRef.current = null;
            root.unmount();
            slot.remove();
        };
    }, []);
    reactExports.useEffect(() => {
        if (slotRef.current) slotRef.current.render(jsxRuntimeExports.jsx(reactExports.Fragment, { children }));
    });
    return null;
}
export { AudioMigrationPage, LogoLibraryPage, ADMIN_TOKEN_KEY, AdminPage, AdminRings, AdminTitles, HistoryPage, SideDoor, adminCall, adminToken, ringBtn, trayArrow };

/* ---- logo library: phrase data through the existing apply/publish door ----------
 * Saving stages only this data file. Publishing remains the code page's action.
 * Draft source is compared again before a save; never silently overwrite work.
 */
async function readPhraseSource() {
    const draft = await adminCall(`/repo/draft?path=${LIBRARY_PATH}`);
    if (draft.ok) return (await draft.json()).content;
    if (draft.status !== 404) throw new Error('the library did not load');
    const live = await adminCall(`/repo/file?path=${LIBRARY_PATH}`);
    if (!live.ok) throw new Error('the library did not load');
    return (await live.json()).content;
}
function LogoPreview({ phrase, roll }) {
    const [frame, setFrame] = reactExports.useState({ text: '', caret: 0 });
    reactExports.useEffect(() => {
        if (!phrase) { setFrame({ text: '', caret: 0 }); return; }
        let life;
        try { life = generateLife(phrase); } catch { setFrame({ text: phrase.text, caret: phrase.text.length }); return; }
        if (matchMedia('(prefers-reduced-motion: reduce)').matches) {
            setFrame({ text: life.word, caret: life.word.length }); return;
        }
        const ending = life.hand.deaths[Math.floor(randomUnit() * life.hand.deaths.length)];
        const frames = [...life.birth, { text: life.word, caret: life.word.length, wait: life.hand.rest[0] }, ...generateDeath(life, ending)];
        let timer, at = 0;
        const step = () => {
            if (at >= frames.length) {
                life = generateLife(phrase);
                const ending = life.hand.deaths[Math.floor(randomUnit() * life.hand.deaths.length)];
                frames.splice(0, frames.length, ...life.birth, { text: life.word, caret: life.word.length, wait: life.hand.rest[0] }, ...generateDeath(life, ending));
                at = 0;
            }
            const next = frames[at++]; setFrame(next); timer = setTimeout(step, next.wait);
        };
        step(); return () => clearTimeout(timer);
    }, [phrase, roll]);
    return jsxRuntimeExports.jsx('div', { className: 'logo-preview', role: 'img', 'aria-label': phrase?.text ?? 'logo preview', children:
        jsxRuntimeExports.jsxs('span', { className: 'logo-word', children: frame.sel ? [
            frame.text.slice(0, frame.sel[0]), jsxRuntimeExports.jsx('span', { className: 'logo-sel', children: frame.text.slice(frame.sel[0], frame.sel[1]) }), frame.text.slice(frame.sel[1]),
        ] : [frame.text.slice(0, frame.caret), jsxRuntimeExports.jsx('span', { className: 'logo-caret rest' }), frame.text.slice(frame.caret)] }),
    });
}
/* the scope labels type themselves: each label runs its own random cycle (type, rest, erase some or all, retype).
   The full label stays in the layout, invisible, so the width never moves; reduced motion keeps it still. */
function TypeLabel({ text }) {
    const [n, setN] = reactExports.useState(text.length);
    reactExports.useEffect(() => {
        if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) return undefined;
        let timer;
        let k = text.length;
        const rand = (lo, hi) => lo + Math.random() * (hi - lo);
        const show = (v) => { k = v; setN(v); };
        const typeTo = (goal, then) => {
            const step = () => {
                if (k < goal) { show(k + 1); timer = window.setTimeout(step, rand(55, 130)); }
                else then();
            };
            step();
        };
        const eraseTo = (goal, then) => {
            const step = () => {
                if (k > goal) { show(k - 1); timer = window.setTimeout(step, rand(35, 80)); }
                else then();
            };
            step();
        };
        const cycle = () => {
            timer = window.setTimeout(() => {
                const keep = Math.random() < 0.5 ? 0 : Math.floor(rand(1, Math.max(2, text.length - 1)));
                eraseTo(keep, () => { timer = window.setTimeout(() => typeTo(text.length, cycle), rand(250, 900)); });
            }, rand(2500, 7000));
        };
        timer = window.setTimeout(cycle, rand(300, 4000));
        return () => window.clearTimeout(timer);
    }, [text]);
    return jsxRuntimeExports.jsxs('span', { className: 'type-label', children: [
        jsxRuntimeExports.jsx('span', { className: 'type-label-full', 'aria-hidden': true, children: text }),
        jsxRuntimeExports.jsx('span', { className: 'type-label-now', 'aria-hidden': true, children: text.slice(0, n) }),
    ] });
}
function LogoLibraryPage({ go }) {
    const [data, setData] = reactExports.useState(null);
    const [textL, setTextL] = reactExports.useState('');
    const [textR, setTextR] = reactExports.useState('');
    const [side, setSide] = reactExports.useState('main');
    const labels = {main:'middots',beta:'middots beta',admin:'middots admin'};
    const [trial, setTrial] = reactExports.useState(null);
    const [panel, setPanel] = reactExports.useState(false);
    /* the preview obeys the text measure (the admin's verizon): a hidden probe as wide as --measure is watched
       and handed to the preview frame as its widest size */
    const measureProbe = reactExports.useRef(null);
    const [measurePx, setMeasurePx] = reactExports.useState(null);
    reactExports.useLayoutEffect(() => {
        const probe = measureProbe.current;
        if (!probe) return undefined;
        const read = () => { const w = probe.getBoundingClientRect().width; if (w) setMeasurePx(w); };
        read();
        const watch = new ResizeObserver(read);
        watch.observe(probe);
        return () => watch.disconnect();
    }, [data]);
    const [selected, setSelected] = reactExports.useState('');
    const [roll, setRoll] = reactExports.useState(0);
    const [choosing, setChoosing] = reactExports.useState(false);
    const [gifBusy, setGifBusy] = reactExports.useState(false);
    const [busy, setBusy] = reactExports.useState(false);
    const [note, setNote] = reactExports.useState('');
    const base = reactExports.useRef(null);
    const [buttonSet, setButtonSetState] = reactExports.useState(currentButtonSet);
    const [ringOff, setRingOffState] = reactExports.useState(readRingOff);
    reactExports.useEffect(() => { let active = true; void readLiveSelection(null).then((live) => { if (active && live) { setButtonSetState(live.buttonSet); setRingOffState(live.ringOff); } }); return () => { active = false; }; }, []);
    const localKey = 'middots-tango-unapplied';
    reactExports.useEffect(() => {
        let active = true;
        void readPhraseSource().then(async (source) => {
            if (!active) return;
            const loaded = normalizeLibrary(JSON.parse(source)); base.current = source;
            let draft = loaded;
            try { const local = JSON.parse(localStorage.getItem(localKey) || 'null'); if (local) { draft = normalizeLibrary(local); setNote('unapplied changes restored'); } } catch { }
            const liveScope = await readHomeLogo(loaded.homeLogo);
            if (!active) return;
            draft = {...draft, homeLogo:liveScope};
            setData(draft); setSelected(draft.phrases[0]?.id ?? 'built:main:0');
        }).catch((e) => { if (active) setNote(e.message); });
        return () => { active = false; };
    }, []);
    const change = (next) => {
        setData(next);
        try { localStorage.setItem(localKey, JSON.stringify(next)); } catch { setNote('this device could not keep unapplied changes'); }
    };
    const chooseHomeLogo = async (scope) => {
        if (busy || scope === data?.homeLogo) return;
        setBusy(true); setNote('');
        try {
            const saved = await writeHomeLogo(scope, adminCall);
            change({...data, homeLogo:saved.homeLogo});
            setHomeLogo(saved.homeLogo);
            setNote('home logo saved live');
        } catch (e) { setNote(e.message || 'live logo was not saved'); }
        finally { setBusy(false); }
    };
    const chooseButtonSet = async (choice) => {
        const set = choice === 'old' ? 'old' : 'new';
        const off = choice === 'new no ring';
        if (busy || (set === buttonSet && (set === 'old' || off === ringOff))) return;
        setBusy(true); setNote('');
        try {
            const saved = await writeButtonSet(set, adminCall, set === 'new' ? off : undefined);
            setButtonSetState(saved.buttonSet); setRingOffState(saved.ringOff);
            applyButtonSet(saved.buttonSet);
            setNote('ui button set saved live: ' + choice);
        } catch (e) { setNote(e.message || 'live button set was not saved'); }
        finally { setBusy(false); }
    };
    const builtIn = reactExports.useMemo(() => ['main', 'beta', 'admin'].flatMap((scope) => (scope === 'beta' ? BETA_WORDS : LOGO_WORDS[scope]).map((word, i) => ({ id: `built:${scope}:${i}`, scope, word, row: scope === 'beta' ? BETA_PHRASES[i] : null }))), []);
    const switchSide = (scope) => { setSide(scope); setSelected(`built:${scope}:0`); setTrial(null); setPanel(false); setTextL(''); setTextR(''); setRoll(n=>n+1); };
    const builtRow = selected.startsWith('built:') ? builtIn.find((b) => b.id === selected) : null;
    const saved = data?.phrases.find((row) => row.id === selected);
    const phrase = saved ?? (builtRow ? (() => { try { return { ...builtRow.row ?? newPhrase(builtRow.word), logo: builtRow.scope }; } catch { return null; } })() : null);
    const shown = trial ?? phrase;
    const update = (patch) => change({ ...data, phrases: data.phrases.map((row) => row.id === selected ? { ...row, ...patch } : row) });
    const pick = (id) => { setSelected(id); setTrial(null); setRoll((n) => n + 1); };
    const add = (event) => {
        event?.preventDefault();
        try {
            const rows = textL.trim() ? [newPhrase(textL.trim(), undefined, side)] : [];
            if (!rows.length) return;
            change({ ...data, phrases: [...data.phrases, ...rows] }); setSelected(rows[0].id); setTrial(null); setTextL(''); setTextR(''); setNote(''); setRoll((n) => n + 1);
        } catch (e) { setNote(e.message); }
    };
    const downloadGif = async () => {
        const word = document.querySelector('.logo-panel-canvas .logo-word'); if (!word || !shown) return;
        setGifBusy(true); setNote('');
        try {
            await document.fonts?.ready;
            const cs = getComputedStyle(word), panel = getComputedStyle(word.closest('.logo-panel-canvas'));
            const probe = document.createElement('span'); probe.className = 'logo-sel'; word.parentElement.appendChild(probe);
            const hair = getComputedStyle(probe).backgroundColor; const ink = getComputedStyle(probe).color; probe.remove();
            const caretEl = document.querySelector('.logo-panel-canvas .logo-caret');
            const size = parseFloat(cs.fontSize), spacing = parseFloat(cs.letterSpacing) || 0;
            const look = { width: 800, height: 200, maxWidth: 732, size, spacing, font: `${cs.fontStyle} ${cs.fontWeight} ${cs.fontSize} ${cs.fontFamily}`, bg: panel.backgroundColor, dim: cs.color, ink, hairline: hair, caret: caretEl ? getComputedStyle(caretEl).backgroundColor : '#dc143c' };
            const life = generateLife(shown);
            const ending = life.hand.deaths[Math.floor(randomUnit() * life.hand.deaths.length)];
            const frames = [...life.birth, { text: life.word, caret: life.word.length, wait: life.hand.rest[0] }, ...generateDeath(life, ending)];
            saveBlob(await logoGifBlob(frames, look), `middots-logo-${(shown.text || 'logo').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'logo'}.gif`);
            setChoosing(false);
        } catch (e) { setNote(e.message || 'the download failed'); }
        finally { setGifBusy(false); }
    };
    const play = () => {
        const t = textL.trim();
        if (t) { try { setTrial(newPhrase(t, undefined, side)); setNote(''); } catch (e) { setNote(e.message); return; } } else setTrial(null);
        setRoll((n) => n + 1);
    };
    const edit = () => {
        if (builtRow) { try { const row = builtRow.row ? {...builtRow.row, id: crypto.randomUUID()} : newPhrase(builtRow.word, undefined, builtRow.scope); change({ ...data, phrases: [...data.phrases, row] }); setSelected(row.id); setPanel(true); } catch (e) { setNote(e.message); } return; }
        if (saved) setPanel(!panel);
    };
    const options = [
        ...(data?.phrases ?? []).filter(row => row.logo === side || (row.logo === 'both' && side !== 'beta')).map(row => ({value:row.id,label:row.text,tag:labels[side]})),
        ...builtIn.filter(b=>b.scope===side).map(b=>({value:b.id,label:b.word,tag:`${labels[side]} · built in`})),
    ];
    const save = async () => {
        setBusy(true); setNote('');
        try {
            const checked = normalizeLibrary({...data, homeLogo:await readHomeLogo(data.homeLogo)});
            const latest = await readPhraseSource();
            if (latest !== base.current) throw new Error('the library changed elsewhere - reload before saving');
            const content = JSON.stringify(checked, null, 2) + '\n';
            const response = await adminCall('/repo/draft', { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ path: LIBRARY_PATH, content }) });
            if (!response.ok) throw new Error('the save failed - nothing applied');
            base.current = content; setData(checked); setLibrary(checked);
            try { localStorage.removeItem(localKey); } catch { }
            setNote('saved to preview. publish from code.');
        } catch (e) { setNote(e.message); }
        finally { setBusy(false); }
    };
    const rangeLabels = { key: 'typing ms', seam: 'pause ms', slip: 'error chance', notice: 'notice ms', erase: 'erase ms', rest: 'hold ms', deathMul: 'end pace' };
    const endingLabels = { steady: 'backspace', held: 'held backspace', cut: 'clear', selectall: 'select all', front: 'forward delete', growsel: 'backward selection' };
    const field = (key) => jsxRuntimeExports.jsxs('div', { className: 'logo-range', children: [
        jsxRuntimeExports.jsx('span', { children: rangeLabels[key] }),
        ...[0, 1].map((side) => jsxRuntimeExports.jsx(Stepper, { step: key === 'slip' || key === 'deathMul' ? .01 : 1,
            min: RANGE_LIMITS[key][0], max: RANGE_LIMITS[key][1], value: phrase.ranges[key][side], disabled: busy,
            label: `${rangeLabels[key]} ${side ? 'maximum' : 'minimum'}`, onChange: (v) => {
                const range = [...phrase.ranges[key]]; range[side] = v;
                update({ ranges: { ...phrase.ranges, [key]: range } });
            } }, `${key}-${side}`)),
    ] }, key);
    return jsxRuntimeExports.jsxs('div', { className: 'admin-page logo-library-page', children: [
        jsxRuntimeExports.jsx('div', { className: 'logo-slot', children: jsxRuntimeExports.jsx(Logo, { admin: true }) }),
        jsxRuntimeExports.jsx(AdminTitles, { go, on: 'admin/logo' }),
        jsxRuntimeExports.jsx('div', { className: 'story editor-story open', children:
            jsxRuntimeExports.jsx('div', { className: 'story-fold editor-fold', children:
                jsxRuntimeExports.jsxs('div', { className: 'story-body editor-body mailing-body', children: [
                    jsxRuntimeExports.jsxs('div', {className:'logo-scope-row', role:'tablist', 'aria-label':'logo panel', children: ['main','beta','admin'].flatMap((scope,i)=>[i ? jsxRuntimeExports.jsx('span',{ 'aria-hidden':true, children:' · · '},`sep-${scope}`):null,jsxRuntimeExports.jsx('button',{role:'tab','aria-selected':side===scope,'aria-label':labels[scope],onClick:()=>switchSide(scope),children:jsxRuntimeExports.jsx(TypeLabel,{text:labels[scope]})},scope)])}),
                    data && jsxRuntimeExports.jsxs('div',{className:'logo-home-choice',children:[jsxRuntimeExports.jsx('span',{children:'home page logo'}),...['main','beta'].map(scope=>jsxRuntimeExports.jsx(Toggle,{on:data.homeLogo===scope,disabled:busy,onChange:()=>void chooseHomeLogo(scope),children:labels[scope]},scope))]}),
                    data && jsxRuntimeExports.jsxs('div',{className:'logo-home-choice',children:[jsxRuntimeExports.jsx('span',{children:'ui button'}),...['old','new','new no ring'].map(set=>jsxRuntimeExports.jsx(Toggle,{on:set==='old'?buttonSet==='old':(buttonSet==='new'&&ringOff===(set==='new no ring')),disabled:busy,onChange:()=>void chooseButtonSet(set),children:set},set))]}),
                    jsxRuntimeExports.jsx('div', { key: 'measure-probe', ref: measureProbe, 'aria-hidden': true, style: { width: 'var(--measure)', height: 0, overflow: 'hidden', pointerEvents: 'none' } }),
                    jsxRuntimeExports.jsx(AdminPreviewFrame, { className: 'logo-panel', maxWidth: measurePx,  children:
                        jsxRuntimeExports.jsx('div', { className: 'mailing-frame logo-panel-canvas', onClick: (e) => e.stopPropagation(), onPointerMove: (e) => e.stopPropagation(), children:
                            [shown ? jsxRuntimeExports.jsx(LogoPreview, { key: 'lp', phrase: shown, roll }) : jsxRuntimeExports.jsx(Logo, { key: 'lg', admin: true }),
                            shown && jsxRuntimeExports.jsx('div', { key: 'hit', className: `mailing-hit${choosing ? ' open' : ''}`, role: 'button', tabIndex: 0, 'aria-label': 'download the logo gif',
                                onClick: () => setChoosing(!choosing), onKeyDown: (e) => { if (e.key === 'Escape') setChoosing(false); if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); setChoosing(!choosing); } },
                                children: choosing ? jsxRuntimeExports.jsx('span', { className: 'mailing-formats', children: jsxRuntimeExports.jsxs('span', { className: 'mailing-format', children: [
                                    jsxRuntimeExports.jsx(GlyphButton, { glyph: 'gif', className: 'big', tip: gifBusy ? 'preparing' : 'download gif', disabled: gifBusy, onClick: (e) => { e.stopPropagation(); void downloadGif(); } }),
                                    jsxRuntimeExports.jsx('span', { className: 'mailing-format-name', children: 'gif' }),
                                ] }) }) : null })] }),
                    }),
                    data && jsxRuntimeExports.jsxs('form', { className: 'logo-phrase-add', onSubmit: add, children: [
                        jsxRuntimeExports.jsx('input', { key: 'l', className: 'logo-phrase-text', value: textL, disabled: busy, 'aria-label': `${labels[side]} phrase`, placeholder: labels[side], onChange: (e) => setTextL(e.target.value) }),
                        jsxRuntimeExports.jsx(GlyphButton, { key: 'p', glyph: 'plus', type: 'submit', tip: 'add', disabled: busy || !(textL.trim() || textR.trim()) }),
                        jsxRuntimeExports.jsx(PlayButton, { key: 'y', onClick: play, tip: 'play' }),
                    ] }),
                    data && jsxRuntimeExports.jsxs('div', { className: 'logo-pick', children: [
                        jsxRuntimeExports.jsx(Drop, { key: 'd', value: selected, options, onPick: pick, label: 'recorded logo phrases', disabled: busy }),
                        jsxRuntimeExports.jsx(GlyphButton, { key: 'e', glyph: 'edit', onClick: edit, tip: builtRow ? 'copy to edit' : 'edit', disabled: busy || !phrase }),
                        jsxRuntimeExports.jsx(GlyphButton, { key: 'x', glyph: 'cross', tip: 'delete', disabled: busy || !saved, onClick: () => { change({ ...data, phrases: data.phrases.filter((row) => row.id !== selected) }); setSelected(''); setTrial(null); setPanel(false); } }),
                        jsxRuntimeExports.jsx(GlyphButton, { key: 's', glyph: 'save', tip: busy ? 'saving' : 'save to preview', disabled: busy, onClick: () => void save() }),
                    ] }),
                    saved && panel && jsxRuntimeExports.jsxs('div', { className: 'logo-edit', children: [
                        jsxRuntimeExports.jsx('input', { key: 'tx', className: 'logo-phrase-text', value: saved.text, disabled: busy, 'aria-label': 'phrase text', onChange: (e) => update({ text: e.target.value }) }),
                        jsxRuntimeExports.jsx('p', { key: 'mm', className: 'admin-note', children: 'min / max' }),
                        ...Object.keys(DEFAULT_RANGES).map(field),
                        jsxRuntimeExports.jsx('div', { key: 'en', className: 'logo-toggles', children: DEATH_NAMES.map((name) => jsxRuntimeExports.jsx(Toggle, { on: saved.deaths.includes(name), disabled: busy,
                            onChange: (v) => update({ deaths: v ? [...saved.deaths, name] : saved.deaths.filter((d) => d !== name) }), children: endingLabels[name] }, name)) }),
                    ] }),
                    note && jsxRuntimeExports.jsx('p', { className: 'admin-note', role: 'status', children: note }),
                ] }),
            }),
        }),
    ] });
}


/* No token input/export/persistence. The existing admin session stays within this page. */
function AudioMigrationPage({ go }) {
    const [note, setNote] = reactExports.useState('load plan.json; ops must open the freeze window before running');
    const [busy, setBusy] = reactExports.useState(false);
    const [ready, setReady] = reactExports.useState(false);
    const [, redraw] = reactExports.useState(0);
    const runnerRef = reactExports.useRef(null);
    if (!runnerRef.current) {
        const session = adminToken();
        runnerRef.current = new AudioMigration((path, init = {}) => {
            if (!session || adminToken() !== session) throw Error('admin session changed; reopen this room');
            return fetch(SYNC_URL + path, { ...init, redirect: 'error', cache: 'no-store',
                headers: { ...init.headers, Authorization: `Bearer ${session}` } });
        }, setNote);
    }
    const runner = runnerRef.current;
    reactExports.useEffect(() => () => { runner.stop = true; }, [runner]);
    const run = async phase => {
        if (runner.busy) return;
        setBusy(true); setNote('checking owner/admin freeze status');
        try { await runner.run(phase); } catch (e) { setNote(e.message === 'Failed to fetch' ? 'request failed; stopped without marking the frame verified' : e.message); }
        finally { setBusy(false); redraw(n => n + 1); }
    };
    const load = async event => {
        const file = event.target.files?.[0]; event.target.value = '';
        if (!file) return;
        try {
            if (file.size > 262144) throw Error('plan too large');
            runner.load(JSON.parse(await file.text())); setReady(true);
            setNote(`${runner.entries.length} files · ${runner.entries.reduce((n,e) => n + e.frames, 0)} frames · ${runner.entries.reduce((n,e) => n + e.size, 0)} bytes`);
        } catch (e) { setNote(e.message); }
        redraw(n => n + 1);
    };
    const exportReport = () => {
        const url = URL.createObjectURL(new Blob([JSON.stringify(runner.report(), null, 2)], { type: 'application/json' }));
        const a = document.createElement('a'); a.href = url; a.download = 'audio-migration-report.json'; a.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
    };
    const button = (name, phase, disabled) => jsxRuntimeExports.jsx('button', { type: 'button', className: 'admin-add', disabled: busy || disabled, onClick: () => void run(phase), children: name });
    const before = ready && runner.entries.every(e => runner.before[e.file]);
    const complete = ready && runner.done.size === runner.entries.reduce((n,e) => n + e.frames, 0);
    return jsxRuntimeExports.jsxs('div', { className: 'admin-page audio-migration-page', children: [
        jsxRuntimeExports.jsx('div', { className: 'logo-slot', children: jsxRuntimeExports.jsx(Logo, { admin: true }) }),
        jsxRuntimeExports.jsx(AdminTitles, { go, on: 'admin/audio' }),
        jsxRuntimeExports.jsx('div', { className: 'story editor-story open', children: jsxRuntimeExports.jsx('div', { className: 'story-fold editor-fold', children:
            jsxRuntimeExports.jsxs('div', { className: 'story-body editor-body', children: [
                jsxRuntimeExports.jsx('p', { className: 'admin-note', children: 'KV → B2 · originals stay in KV' }),
                jsxRuntimeExports.jsx('label', { className: 'audio-plan', children: jsxRuntimeExports.jsx('input', { type: 'file', accept: '.json,application/json', disabled: busy || runner.done.size > 0, 'aria-label': 'load audio migration plan', onChange: load }) }),
                jsxRuntimeExports.jsxs('div', { className: 'audio-migration-actions', children: [
                    button('1. before hashes', 'before', !ready || runner.done.size > 0),
                    button('2. migrate first two files', 'bounded', !before),
                    button('3. migrate all remaining files', 'full', !before || !runner.bounded),
                    button('4. verify playback hashes', 'verify', !complete),
                    jsxRuntimeExports.jsx('button', { type: 'button', className: 'admin-add', disabled: !busy, onClick: () => { runner.stop = true; setNote('stop requested; waiting for the current request'); }, children: 'stop after current request' }),
                    jsxRuntimeExports.jsx('button', { type: 'button', className: 'admin-add', disabled: busy || !ready, onClick: exportReport, children: 'download hash report (no session token)' }),
                ] }),
                jsxRuntimeExports.jsx('p', { role: 'status', 'aria-live': 'polite', className: 'admin-note audio-migration-status', children: note }),
                jsxRuntimeExports.jsx('p', { className: 'admin-note', children: 'One request at a time. A 503 is retried once; any unverified frame stops the run. Keep this room open. Reloading discards the baseline and progress; download the report first. No automatic unfreeze or KV deletion.' }),
                ...runner.entries.map(e => jsxRuntimeExports.jsx('p', { className: 'audio-migration-file', children: `${e.file} · ${e.frames} frames · ${runner.after[e.file] ? 'hash match' : runner.before[e.file] ? 'before hash saved' : 'pending'}` }, e.file)),
            ] }) }) }),
    ] });
}

