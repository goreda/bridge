import { ADMIN_PROFILE_STATE_VERSION, cleanLane, cleanAdminProfileState } from './admin-profile-state.js?v=20261027-f7-held-keys-r1';
import { durability } from './admin-transcribe-durability.js?v=20261027-f7-held-keys-r1';
import { startAdminProbe } from './admin-probe.js?v=20261027-f7-held-keys-r1';
import { cleanPalette, applyPalette } from './palette.js?v=20261027-f7-held-keys-r1';
import { unit as randomUnit } from './random.js?v=20261027-f7-held-keys-r1';
import { UiPresetsContext, cleanUiPresets, migrateAdminFolds } from './ui-presets.js?v=20261027-f7-held-keys-r1';
import { InstinctShelf } from './bridge.js?v=20261027-f7-held-keys-r1';
import { FOLDERS, PIECES, STATE_KEY, SYNC_URL, closingInText, deletePrivate, folderOf, loadPrivate, token$1 } from './pieces.js?v=20261027-f7-held-keys-r1';
import { UPLOADED, doorFaces, faceBySlug, loadFace, variationSettings } from './faces.js?v=20261027-f7-held-keys-r1';
import { currentWrite, retryMerged, syncReady, acceptArchive, currentRead, isJoined, onNewer, onSignedOut, pull, pushNow, acceptRemote, pushMerged, getBase, schedulePush, syncAvailable, token, noteAdminProbe, currentAttempt, recoveryRecords } from './sync.js?v=20261027-f7-held-keys-r1';
import { mergeStates } from './state-merge.js?v=20261027-f7-held-keys-r1';
import { scopeForToken, cachedScope, packState, readScopedState } from './state-scope.js?v=20261027-f7-held-keys-r1';

/* The identity this page booted under. The live library's provenance: content the page holds
 * was loaded for THIS identity, so it may only ever be written back under it. After a leave /
 * wipe mid-session the token disappears; without this gate a debounced save would re-pack the
 * gone profile's library as an ANONYMOUS copy - readable by every later session here, the exact
 * leak card 20261024-001 closes. An anonymous boot keeps the empty sentinel: its content may be
 * written under a later join (the designed first-join import). (card 20261024-001 rider) */
const bootStateToken = token();
import { cleanPresentation, isShareEntry } from './share.js?v=20261027-f7-held-keys-r1';
import { findActiveShare, folderPayloadOf, folderShareUrl, forgetShareUrl, mintShare, piecePayloadOf, recalledShareUrl, registerShareRef, rememberShareUrl, revokeShareOp } from './share-ops.js?v=20261027-f7-held-keys-r1';
import { loadShare, parseShareHash } from './share-view.js?v=20261027-f7-held-keys-r1';
import { clearSyncNotes, handleMergeReceipt, saveRecovery, showNote, piecesOf } from './sync-recovery.js?v=20261027-f7-held-keys-r1';
import { addFontFile, forgetAllFonts, removeFont, restoreFonts, shareLocalFonts } from './uploads.js?v=20261027-f7-held-keys-r1';
import { PDF_LIVE, collect, exportPdf, saveBytes, toDocx, toTxt } from './export.js?v=20261027-f7-held-keys-r1';
import { AddPlus, ArchiveEnd, Cover, LOGO_ROAMING, Logo, Story, logoMode } from './reading.js?v=20261027-f7-held-keys-r1';
import { ControlGroup, HorizonControl, INDEX_PT, INDEX_W, IndexHide, IndexTick, MeasureTick, PdfPick, SNAP_MAX, SizeField, TEXT_PT, WIDTH_EM, clampHz, clampPt, flatLines, hzMax, nowStamp, sameLines, withSnap } from './controls.js?v=20261027-f7-held-keys-r1';
import { ERA_TIPS, FxPalette, WorkStory, pieceSnapshots, attachCommit, attachTypeSound, readParas, readTitle, storeGet, storeSet } from './draft.js?v=20261027-f7-held-keys-r1';
import { FacePicker, findInElement } from './faces-ui.js?v=20261027-f7-held-keys-r1';
import { LAYOUTS, LAYOUT_DEFAULT } from './layout-ui.js?v=20261027-f7-held-keys-r1';
import { SearchControl } from './search.js?v=20261027-f7-held-keys-r1';
import { SyncControl, readFolders, viewFromHash } from './account.js?v=20261027-f7-held-keys-r1';
import { ADMIN_TOKEN_KEY, AudioMigrationPage, LogoLibraryPage, AdminPage, HistoryPage, adminToken } from './admin.js?v=20261027-f7-held-keys-r1';
import { ChangesPage, EditorPage } from './admin-code.js?v=20261027-f7-held-keys-r1';
import { MailingPage } from './admin-mailing.js?v=20261027-f7-held-keys-r1';

import {
    r as reactExports,
    j as jsxRuntimeExports,
    R as React,
    c as createRoot,
} from './vendor.js?v=20261027-f7-held-keys-r1';
import { ERAS, warmAudio, playSound, classifyKeydown, calibrateSound } from './audio.js?v=20261027-f7-held-keys-r1';
import { installUIMotion } from './ui-motion.js?v=20261027-f7-held-keys-r1';
import { MOBILE_QUERY, layoutDevice, layoutOnly, migrateLayouts, cleanPieceLayouts, effectivePieceLayout, payloadPieceLayouts, withPieceLayoutField, withoutPieceLayoutLane } from './layout-profile.js?v=20261027-f7-held-keys-r1';
import { renderApp } from './app-view.js?v=20261027-f7-held-keys-r1';
import { makeImporter, makeSettingsImporter } from './app-import.js?v=20261027-f7-held-keys-r1';
import './tip-type.js?v=20261027-f7-held-keys-r1';
import './hover-icon.js?v=20261027-f7-held-keys-r1';
import './button-set.js?v=20261027-f7-held-keys-r1';
import './release-watch.js?v=20261027-f7-held-keys-r1';
/* ---- App -----------------------------------------------------------------
 * Top-level state, effects and the control column. Effects are grouped:
 * appearance -> scrolling/pinning -> draft mode -> export/import.
 */
const EMPTY_PALETTE = Object.freeze({});
/* Ghost controls share their 1800ms activity gate with automatic writing focus.
   The owner App and the read-only share view run the same wake wiring. */
const useChromeAwake = (scrollerRef, deps) => reactExports.useEffect(() => {
    const root = document.documentElement;
    const IDLE_MS = 1800;
    let timer, typingTimer, composing = false, typing = false;
    let over = false;
    const writer = target => {
        const el = target?.closest?.('.editable, .code-input');
        return el && (el.isContentEditable || (el.matches('textarea') && !el.readOnly && !el.disabled));
    };
    const resting = () => over &&
        [...document.querySelectorAll(':hover')].some(el => el.closest?.('.controls'));
    const wake = e => {
        const t = e?.target;
        if (e && (e.type === 'mousemove' || e.type === 'pointerover'))
            over = !!t?.closest?.('.controls');
        if (typing) return; // Pointer movement and platen scrolling cannot wake chrome mid-sentence.
        root.classList.add('ui-awake');
        window.clearTimeout(timer);
        timer = window.setTimeout(() => {
            if (!resting()) root.classList.remove('ui-awake');
        }, IDLE_MS);
    };
    const finishTyping = () => {
        window.clearTimeout(typingTimer);
        composing = false;
        if (!typing) return;
        typing = false;
        root.classList.remove('typing-focus');
        window.dispatchEvent(new CustomEvent('typing-focus', { detail: false }));
        wake(); // Return the controls, then let their usual idle fade take over.
    };
    const beginTyping = e => {
        if (!writer(e.target)) return;
        window.clearTimeout(timer);
        window.clearTimeout(typingTimer);
        if (!typing) {
            typing = true;
            root.classList.add('typing-focus');
            root.classList.remove('ui-awake');
            window.dispatchEvent(new CustomEvent('typing-focus', { detail: true }));
        }
        if (!composing) typingTimer = window.setTimeout(finishTyping, IDLE_MS);
    };
    const onKey = e => {
        const edits = !e.metaKey && !e.ctrlKey && !e.altKey &&
            (e.key.length === 1 || ['Enter', 'Backspace', 'Delete', 'Tab'].includes(e.key));
        if (writer(e.target) && edits) beginTyping(e);
        else wake(e);
    };
    const onCompositionStart = e => {
        if (!writer(e.target)) return;
        composing = true;
        beginTyping(e);
    };
    const onCompositionEnd = e => {
        if (!writer(e.target)) return;
        composing = false;
        beginTyping(e);
    };
    const onFocus = e => { if (!writer(e.target)) finishTyping(); };
    const onTouchEnd = () => { over = false; };
    window.addEventListener('pointerover', wake, { passive: true });
    window.addEventListener('mousemove', wake, { passive: true });
    window.addEventListener('touchstart', wake, { passive: true });
    window.addEventListener('touchend', onTouchEnd, { passive: true });
    window.addEventListener('keydown', onKey);
    document.addEventListener('beforeinput', beginTyping, true);
    document.addEventListener('input', beginTyping, true);
    document.addEventListener('compositionstart', onCompositionStart, true);
    document.addEventListener('compositionend', onCompositionEnd, true);
    document.addEventListener('focusin', onFocus);
    window.addEventListener('blur', finishTyping);
    const sc = scrollerRef.current;
    sc?.addEventListener('scroll', wake, { passive: true });
    return () => {
        window.removeEventListener('mousemove', wake);
        window.removeEventListener('pointerover', wake);
        window.removeEventListener('touchstart', wake);
        window.removeEventListener('touchend', onTouchEnd);
        window.removeEventListener('keydown', onKey);
        document.removeEventListener('beforeinput', beginTyping, true);
        document.removeEventListener('input', beginTyping, true);
        document.removeEventListener('compositionstart', onCompositionStart, true);
        document.removeEventListener('compositionend', onCompositionEnd, true);
        document.removeEventListener('focusin', onFocus);
        window.removeEventListener('blur', finishTyping);
        sc?.removeEventListener('scroll', wake);
        finishTyping();
        window.clearTimeout(timer);
    };
}, deps);

/* the per-piece layout as CSS variables: the same resolved values the global rails set,
   scoped to one story. The owner's reading page and the recipient's share view both use it. */
const pieceLayoutStyleOf = (effective) => {
    const textFace = faceBySlug(effective.textFace) ?? faceBySlug('eb-garamond');
    const titleFace = faceBySlug(effective.titleFace) ?? faceBySlug('fragment-mono');
    return {
        '--fs': `${effective.fontSizePt}pt`,
        '--fs-mono': `${effective.indexSizePt}pt`,
        '--measure': `${effective.textWidthEm}em`,
        '--shelf-measure': `${effective.textWidthEm * effective.fontSizePt * 96 / 72}px`,
        '--lh': String(effective.lineHeight),
        '--hz': `${effective.horizon}px`,
        '--font-body': textFace.family,
        '--font-mono': titleFace.family,
        '--fvs-body': variationSettings(textFace.axes, effective.faceAxes?.[textFace.slug]),
        '--fvs-mono': variationSettings(titleFace.axes, effective.faceAxes?.[titleFace.slug]),
    };
};
/* the global layout values as root CSS variables - one formula source for the owner App
   and the recipient share view. --hz stays with the caller (the App clamps and follows
   the platen there); pass horizon to set it. */
export const applyGlobalLayoutVars = ({ fontSizePt, indexSizePt, textWidthEm, lineHeight, horizon }) => {
    const root = document.documentElement;
    root.style.setProperty('--fs', `${fontSizePt}pt`);
    root.style.setProperty('--fs-mono', `${indexSizePt}pt`);
    root.style.setProperty('--measure', `${textWidthEm}em`);
    root.style.setProperty('--shelf-measure', `${textWidthEm * fontSizePt * 96 / 72}px`);
    root.style.setProperty('--lh', String(lineHeight));
    if (horizon !== undefined) root.style.setProperty('--hz', `${horizon}px`);
};
/* faces onto the root: the tasted/chosen slug per slot, its file, its variation knobs */
export const applyFacesTo = (bodySlug, titleSlug, axisValues) => {
    const apply = (slot, slug) => {
        const f =
            faceBySlug(slug) ?? faceBySlug(slot === 'body' ? 'eb-garamond' : 'fragment-mono');
        const prop = slot === 'body' ? '--font-body' : '--font-mono';
        void loadFace(f, true).then(() =>
            document.documentElement.style.setProperty(prop, f.family),
        );
        if (!f.shelf) document.documentElement.style.setProperty(prop, f.family);
        document.documentElement.dataset[slot === 'body' ? 'faceBody' : 'faceTitle'] = f.slug;
        // a variable face is always drawn at its knobs' values ('normal' for every other face)
        document.documentElement.style.setProperty(
            slot === 'body' ? '--fvs-body' : '--fvs-mono',
            variationSettings(f.axes, axisValues[f.slug]),
        );
    };
    apply('body', bodySlug);
    apply('title', titleSlug);
};

function App() {
    reactExports.useEffect(installUIMotion, []);
    const [device, setDevice] = reactExports.useState(layoutDevice);
    const deviceRef = reactExports.useRef(device);
    const layoutProfiles = reactExports.useRef(null);
    const adminProfiles = reactExports.useRef({});
    const adminProfilesRemote = reactExports.useRef(undefined);
    const adminProfilesBinding = reactExports.useRef(null);
    const adminProfilesHeld = reactExports.useRef(false);
    const adminVerifiedBinding = reactExports.useRef(null);
    const adminEditEpoch = reactExports.useRef(0);
    const adminDefaults = () => ({textFace:'fragment-mono',indexFace:'fragment-mono',textPt:10,indexPt:10,textAxes:{},indexAxes:{},lh:1.5,hz:0,textWidthEm:29});
    // Separate raw custody for unreadable admin data found on THIS device (local copy or sync base).
    // Append-only and content-addressed: every distinct raw value is its OWN device key
    // `middots-admin-held:<scope>:<slot>:<sha256>`. Writers never read-modify-write a shared value, so two tabs
    // cannot overwrite each other's custody and ordinary state saves never touch these keys. Never on the wire,
    // never applied as state, bound to the profile scope in key and value, removed by the existing resetDevice prefix sweep.
    const HELD_PREFIX = 'middots-admin-held:';
    const adminCustodyPending = reactExports.useRef([]); // custody not yet confirmed written (storage failure): { scope, slot, raw }
    const adminCustodyDirty = reactExports.useRef(false);
    const custodyScope = () => isJoined() ? cachedScope(token()) : null;
    // synchronous SHA-256 (collision-resistant, so equal key means equal content in practice; no probing needed)
    const sha256Hex = (str) => {
        const bytes = new TextEncoder().encode(str), l = bytes.length, K = [], H = [];
        const isPrime = (n) => { for (let i = 2; i * i <= n; i++) if (n % i === 0) return false; return true; };
        const frac = (x) => ((x - Math.floor(x)) * 4294967296) | 0;
        for (let n = 2, c = 0; c < 64; n++) if (isPrime(n)) { if (c < 8) H[c] = frac(Math.pow(n, 1 / 2)); K[c++] = frac(Math.pow(n, 1 / 3)); }
        const padded = new Uint8Array(((l + 9 + 63) >> 6) << 6); padded.set(bytes); padded[l] = 0x80;
        const dv = new DataView(padded.buffer); dv.setUint32(padded.length - 8, Math.floor(l / 536870912)); dv.setUint32(padded.length - 4, (l << 3) >>> 0);
        const rr = (x, n) => (x >>> n) | (x << (32 - n)), w = new Array(64);
        for (let o = 0; o < padded.length; o += 64) {
            for (let i = 0; i < 16; i++) w[i] = dv.getUint32(o + i * 4);
            for (let i = 16; i < 64; i++) { const s0 = rr(w[i - 15], 7) ^ rr(w[i - 15], 18) ^ (w[i - 15] >>> 3), s1 = rr(w[i - 2], 17) ^ rr(w[i - 2], 19) ^ (w[i - 2] >>> 10); w[i] = (w[i - 16] + s0 + w[i - 7] + s1) | 0; }
            let [a, b, c, d, e, f, g, h] = H;
            for (let i = 0; i < 64; i++) {
                const t1 = (h + (rr(e, 6) ^ rr(e, 11) ^ rr(e, 25)) + ((e & f) ^ (~e & g)) + K[i] + w[i]) | 0, t2 = ((rr(a, 2) ^ rr(a, 13) ^ rr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c))) | 0;
                h = g; g = f; f = e; e = (d + t1) | 0; d = c; c = b; b = a; a = (t1 + t2) | 0;
            }
            H[0] = (H[0] + a) | 0; H[1] = (H[1] + b) | 0; H[2] = (H[2] + c) | 0; H[3] = (H[3] + d) | 0; H[4] = (H[4] + e) | 0; H[5] = (H[5] + f) | 0; H[6] = (H[6] + g) | 0; H[7] = (H[7] + h) | 0;
        }
        return H.map(x => (x >>> 0).toString(16).padStart(8, '0')).join('');
    };
    const heldHash = sha256Hex;
    const loadAdminCustody = (scope = custodyScope()) => {
        const c = { local: [], base: [] };
        const add = (slot, raw) => { if (c[slot] && !c[slot].some(x => JSON.stringify(x) === JSON.stringify(raw))) c[slot].push(raw); };
        try {
            const prefix = HELD_PREFIX + scope + ':';
            for (const k of Object.keys(localStorage)) {
                if (!k.startsWith(prefix)) continue;
                try { const p = JSON.parse(localStorage.getItem(k)); if (p && p.v === 1 && p.scope === scope) add(p.slot, p.raw); } catch { }
            }
        } catch { }
        for (const p of adminCustodyPending.current) if (p.scope === scope) add(p.slot, p.raw);
        return c;
    };
    // write one raw value under its own key; true only when the stored value reads back identical (or is already there)
    const writeHeld = (scope, slot, raw) => {
        const value = JSON.stringify({ v: 1, scope, slot, raw });
        const key = HELD_PREFIX + scope + ':' + slot + ':' + heldHash(JSON.stringify(raw));
        const cur = localStorage.getItem(key);
        if (cur === value) return true;
        if (cur != null) return false; // occupied by different content (needs a SHA-256 collision): fail closed, never overwrite
        localStorage.setItem(key, value);
        return localStorage.getItem(key) === value;
    };
    const flushAdminCustody = () => {
        const left = [];
        for (const p of adminCustodyPending.current) { let ok = false; try { ok = writeHeld(p.scope, p.slot, p.raw); } catch { } if (!ok) left.push(p); }
        adminCustodyPending.current = left;
        adminCustodyDirty.current = left.length > 0;
        return left.length === 0;
    };
    const holdAdminRaw = (slot, raw, scope = custodyScope()) => {
        const text = JSON.stringify(raw);
        if (loadAdminCustody(scope)[slot].some(x => JSON.stringify(x) === text)) return false;
        let ok = false;
        try { ok = writeHeld(scope, slot, JSON.parse(text)); } catch { }
        if (!ok) { adminCustodyPending.current = [...adminCustodyPending.current, { scope, slot, raw: JSON.parse(text) }]; adminCustodyDirty.current = true; }
        return true;
    };
    const packWithCustody = (scope, state) => packState(scope, state);
    // ordinary state write: retry any custody not yet durable, then write + read back the scoped state copy
    const writeScopedWithCustody = (scope, state) => {
        // custody not yet durable: the previous scoped copy still holds the only durable copy of the raw value,
        // so it must NOT be replaced by this write (fail closed; retried by the next save/event)
        if (!flushAdminCustody()) return { stored: null, readback: null, durable: false, held: true };
        const stored = packWithCustody(scope, state);
        localStorage.setItem(STATE_KEY, stored);
        const readback = localStorage.getItem(STATE_KEY);
        return { stored, readback, durable: readback === stored && !adminCustodyDirty.current };
    };
    const repairAdminCustody = () => { try { flushAdminCustody(); } catch { } };
    reactExports.useEffect(() => {
        const onStorage = (e) => { repairAdminCustody(); };
        window.addEventListener('storage', onStorage);
        window.addEventListener('focus', repairAdminCustody);
        window.addEventListener('pagehide', repairAdminCustody);
        return () => { window.removeEventListener('storage', onStorage); window.removeEventListener('focus', repairAdminCustody); window.removeEventListener('pagehide', repairAdminCustody); };
    }, []);
    reactExports.useEffect(() => {
        const media = matchMedia(MOBILE_QUERY);
        const change = () => setDevice(layoutDevice());
        media.addEventListener('change', change);
        return () => media.removeEventListener('change', change);
    }, []);
    const [wipeCurtain, setWipeCurtain] = reactExports.useState(false);
    const [welcome, setWelcome] = reactExports.useState(() => {
        try { return sessionStorage.getItem('middots-wipe-welcome') === '1'; } catch { return false; }
    });
    const finishWelcome = reactExports.useCallback(() => {
        try { sessionStorage.removeItem('middots-wipe-welcome'); } catch { }
        setWelcome(false);
    }, []);
    const [inverted, setInverted] = reactExports.useState(() => storeGet('wt-invert') === '1');
    const [textPt, setTextPt] = reactExports.useState(19);
    const [indexPt, setIndexPt] = reactExports.useState(10);
    const [textWidthEm, setTextWidthEm] = reactExports.useState(29);
    const [indexW, setIndexW] = reactExports.useState(() => {
        const n = parseFloat(storeGet('wt-index-w'));
        return n >= INDEX_W[0] && n <= INDEX_W[1] ? n : 300;
    });
    reactExports.useEffect(() => {
        document.documentElement.style.setProperty('--index-w', `max(200px, min(${indexW}px, 100vw - 444px))`);
        storeSet('wt-index-w', String(indexW));
    }, [indexW]);
    const [uiPresets, setUiPresets] = reactExports.useState(() => cleanUiPresets(null));
    const updateUiPreset = (lane, key, value) => setUiPresets(previous => ({ ...previous, [lane]: { ...previous[lane], [key]: value } }));
    const changeInstinctFold = reactExports.useCallback((id, flag) => setUiPresets(previous => ({ ...previous, instinctViewer: { ...previous.instinctViewer, folds: { ...previous.instinctViewer.folds, [id]: flag } } })), []);
    const uiLane = view => view === 'instinct' ? 'instinctViewer' : view.startsWith('admin') ? 'admin' : 'owner';
    const [open, setOpen] = reactExports.useState(() =>
        PIECES[0] ? { [PIECES[0].id]: true } : {},
    );
    const [mode, setMode] = reactExports.useState('read');
    // the chosen mode is a page-level choice: folder hops keep it until the toggle says otherwise
    const modePrefRef = reactExports.useRef('read');
    /* where the reader is: the main page ('home') or a folder id. Mirrored in the address as #/<folder>,
       so a folder can be linked and the back button leaves it; saved with the rest of the state */
    const [view, setView] = reactExports.useState(() => viewFromHash() ?? 'home');
    const [adminVerified, setAdminVerified] = reactExports.useState(false);
    const [adminSession, setAdminSession] = reactExports.useState(0); // ticks whenever the admin token is settled
    // Admin typography has its own device-local lane. Reader settings never enter it.
    const adminSide = view === 'admin' || view.startsWith('admin/');
    const [adminType, setAdminType] = reactExports.useState(() => ({...adminDefaults(),deviceLane:device}));
    const [adminTaste, setAdminTaste] = reactExports.useState(null);
    const [adminFaceOpen, setAdminFaceOpen] = reactExports.useState(null);
    const updateAdminType = (key,value) => {
        if (!adminVerified || adminVerifiedBinding.current !== token() || adminProfilesBinding.current !== token()) { showNote('admin layout is unavailable until this session is verified'); return; }
        if (adminProfilesHeld.current) { showNote('admin layout data needs review · the existing copy is held unchanged'); return; }
        const previous={...adminDefaults(),...adminProfiles.current[device]};
        const lane=cleanLane({...previous,[key]:typeof value==='function'?value(previous[key]):value});
        if(!lane)return;
        adminEditEpoch.current++;
        adminProfiles.current={...adminProfiles.current,[device]:lane};
        adminProfilesRemote.current={...(adminProfilesRemote.current??{}),version:ADMIN_PROFILE_STATE_VERSION,profiles:adminProfiles.current};
        setAdminType({...lane,deviceLane:device});
    };
    reactExports.useEffect(()=>{
        const verified=adminVerified && adminProfilesBinding.current===token() && !adminProfilesHeld.current;
        setAdminType({...adminDefaults(),...(verified?adminProfiles.current[device]:{}),deviceLane:device});
    },[adminVerified,adminSession]);
    reactExports.useEffect(() => {
        setAdminTaste(null);
        setAdminFaceOpen(null);
    }, [adminSide]);

    const [instinctNavigation, setInstinctNavigation] = reactExports.useState(null);
    // The instinct profile starts from its own fixed defaults (the same ones a fresh reader gets), not from whatever the owner's reader has set.
    const bridgeDefaults = () => ({
        fontSizePt: 19, indexSizePt: 10, textWidthEm: 29, lineHeight: 1.42, background: 'default', palettePages: {}, horizon: 0,
        inverted: false, soundEra: ERAS[2].id, sound: true, platen: false, focusDim: true, commitment: false,
        textFace: 'eb-garamond', titleFace: 'fragment-mono', faceAxes: {},
    });
    const preferenceLane = reactExports.useRef('owner');
    const ownerSettings = reactExports.useRef(null);
    const bridgeSettings = reactExports.useRef(null);
    const switchingPreferences = reactExports.useRef(false);
    // folders made on the page (the + on the main page); saved and synced with the rest of the state
    const [ownFolders, setOwnFolders] = reactExports.useState([]);
    /* share registry: which pieces and folders carry a live link. Synced with the rest of
       the state (the shares key in the payload; mergeStates keeps revocations monotonic). */
    const [shares, setShares] = reactExports.useState([]);
    const sharesRef = reactExports.useRef([]);
    const setSharesBoth = (s) => { sharesRef.current = s; setShares(s); };
    const allFolders = [...FOLDERS, ...ownFolders];
    const liveFolders = () => allFolders.filter((f) => !goneFoldersRef.current.includes(f.id));
    const ownFoldersRef = reactExports.useRef(ownFolders);
    ownFoldersRef.current = ownFolders; // for the back/forward handler, registered once
    const createFolder = (title) => {
        const slug =
            title
                .toLowerCase()
                .replace(/[^a-z0-9]+/g, '-')
                .replace(/^-|-$/g, '')
                .slice(0, 24) || 'folder';
        const id = `f-${slug}-${Date.now().toString(36)}`;
        setOwnFolders((fs) => [...fs, { id, title }]);
        // a new folder opens straight into draft mode with a new piece, caret in its text
        enterDraft(id);
        addDraft(id);
    };
    /* share links: a long press on a piece's middot mints or revokes its link (the bullet);
       a held press on the current folder's jump button seals that folder's bulleted pieces
       into one manifest link. Minting uses the joined token already on this device - no new
       secret. The key lives only in the copied link's fragment; the server stores the sealed
       envelope and nothing else. Re-minting makes a new link: the old one dies with it. */
    const [shareBusy, setShareBusy] = reactExports.useState(false);
    /* the middot notice: keyed on real clipboard outcomes, never on the mint alone */
    const [shareNotice, setShareNotice] = reactExports.useState(null);
    /* the middot 'link copied' note takes itself back; the ready field stays until dismissed */
    reactExports.useEffect(() => {
        if (shareNotice?.kind !== 'copied') return undefined;
        const t = window.setTimeout(() => setShareNotice(null), 2000);
        return () => window.clearTimeout(t);
    }, [shareNotice]);
    /* the clipboard write starts inside the press gesture: iOS grants it only there, and the
       promise-backed ClipboardItem waits for the minted link. A press released before the hold
       completes rejects the promise - nothing is copied. Null where the async clipboard is
       missing; the mint path then falls back to copyShareUrl. */
    const shareClipStart = () => {
        if (!navigator.clipboard?.write || typeof ClipboardItem !== 'function') return null;
        let resolveText, rejectText;
        const text = new Promise((res, rej) => { resolveText = res; rejectText = rej; });
        let item;
        try { item = new ClipboardItem({ 'text/plain': text.then((u) => new Blob([u], { type: 'text/plain' })) }); }
        catch { return null; }
        const session = { ok: false, resolve: resolveText, reject: () => rejectText(new Error('share: press released')) };
        try { session.write = navigator.clipboard.write([item]).then(() => { session.ok = true; }, () => {}); }
        catch { return null; }
        return session;
    };
    /* no clipboard access at all: the link itself, selected, for a manual copy */
    const shareUrlOverlay = (url) => {
        document.querySelector('.share-url-overlay')?.remove();
        const box = document.createElement('div');
        box.className = 'share-url-overlay';
        const field = document.createElement('input');
        field.className = 'share-url-field';
        field.readOnly = true;
        field.value = url;
        field.setAttribute('aria-label', 'share link - copy it by hand');
        box.appendChild(field);
        box.addEventListener('click', (e) => { if (e.target === box) box.remove(); });
        field.addEventListener('keydown', (e) => { if (e.key === 'Escape') box.remove(); });
        document.body.appendChild(box);
        field.focus();
        field.select();
        showNote('clipboard blocked - the link is selected, copy it by hand');
    };
    /* owner order 2026-10-21 09:57-10:02 +03 (relayed by gdb via main 10:05; originals gdb-side):
       the copied confirmation is ONLY the middot notice -
       the line above the piece's own middot, index type, typewriter (reading.js/draft.js
       share-tip). No top-row note, no body type. copyShareUrl itself stays silent. */
    const copyShareUrl = async (url) => {
        try { await navigator.clipboard.writeText(url); return true; }
        catch { return false; }
    };
    /* owner order 2026-10-21 (relayed via main): EVERY hover on a shared middot re-copies the
       link to the clipboard. The url comes from this device's own memory - a link minted on
       another device cannot be re-copied here (the key never crosses the server). Clipboard
       truth: 'link copied' shows only after a real clipboard success; when every clipboard
       path fails, the link itself opens selected for a manual copy. */
    const recopyShare = async (pieceId) => {
        const entry = findActiveShare(sharesRef.current, 'piece', pieceId);
        if (!entry) return;
        const url = recalledShareUrl(entry.id);
        if (!url) return;
        if (await copyShareUrl(url)) setShareNotice({ key: pieceId, kind: 'copied' });
        else shareUrlOverlay(url);
    };
    const togglePieceShare = async (p, clip) => {
        if (shareBusy) { clip?.reject(); return; }
        const t = token$1();
        if (!t) { clip?.reject(); showNote('join this device to share'); return; }
        setShareBusy(true);
        try {
            const existing = findActiveShare(sharesRef.current, 'piece', p.id);
            if (existing) {
                clip?.reject();
                setSharesBoth(await revokeShareOp({ syncUrl: SYNC_URL, token: t, shares: sharesRef.current }, existing.id));
                forgetShareUrl(existing.id);
                saveStateRef.current?.();
                showNote('share link revoked');
            } else {
                const { id, url } = await mintShare({ syncUrl: SYNC_URL, token: t, kind: 'piece', payload: piecePayloadOf(p, capturePresentation(p.id)) });
                rememberShareUrl(id, url);
                setSharesBoth(registerShareRef({ shares: sharesRef.current }, { id, kind: 'piece', ref: p.id }).shares);
                saveStateRef.current?.();
                if (clip) {
                    clip.resolve(url);
                    clip.write.then(() => {
                        if (clip.ok) setShareNotice({ key: p.id, kind: 'copied' });
                        else void copyShareUrl(url).then((ok) => setShareNotice(ok ? { key: p.id, kind: 'copied' } : { key: p.id, kind: 'ready', url }));
                    });
                } else {
                    const ok = await copyShareUrl(url);
                    setShareNotice(ok ? { key: p.id, kind: 'copied' } : { key: p.id, kind: 'ready', url });
                }
            }
        } catch (e) {
            clip?.reject();
            showNote(e?.code === 'too_large' ? 'share failed: the sealed copy is over the 256KiB cap' : 'share failed: no answer from the sync service');
        } finally { setShareBusy(false); }
    };
    const shareFolder = async (folderId) => {
        if (shareBusy) return;
        const t = token$1();
        if (!t) { showNote('join this device to share'); return; }
        /* chain instruction 2026-10-18 (relayed via main, architect scope change - this lane
           did not witness the owner word directly): a folder link shows the folder's COMPLETE
           normal reading list - the visible piece list (unpublished pieces the owner reads
           there included); hidden versions and history never cross. One sealed snapshot,
           no other folders. */
        const list = readingList(folderId);
        if (!list.length) { showNote('nothing in this folder yet'); return; }
        setShareBusy(true);
        try {
            const existing = findActiveShare(sharesRef.current, 'folder', folderId);
            if (existing) {
                setSharesBoth(await revokeShareOp({ syncUrl: SYNC_URL, token: t, shares: sharesRef.current }, existing.id));
                forgetShareUrl(existing.id);
            }
            const laneSnapshot = (pid) => {
                const lanes = pieceLayouts[pid];
                return lanes ? { v: 1, piece: { desktop: lanes.desktop, mobile: lanes.mobile } } : undefined;
            };
            const { id, keyB64url } = await mintShare({ syncUrl: SYNC_URL, token: t, kind: 'folder', payload: folderPayloadOf(list, capturePresentation(null), laneSnapshot) });
            const folderUrl = folderShareUrl(id, keyB64url);
            rememberShareUrl(id, folderUrl);
            setSharesBoth(registerShareRef({ shares: sharesRef.current }, { id, kind: 'folder', ref: folderId }).shares);
            saveStateRef.current?.();
            const copied = await copyShareUrl(folderUrl);
            setShareNotice(copied ? { key: `folder:${folderId}`, kind: 'copied' } : { key: `folder:${folderId}`, kind: 'ready', url: folderUrl });
            if (existing) showNote(copied ? 'fresh folder link copied - the old one is revoked' : 'fresh folder link ready - the old one is revoked');
        } catch (e) {
            showNote(e?.code === 'too_large' ? 'share failed: the sealed copy is over the 256KiB cap' : 'share failed: no answer from the sync service');
        } finally { setShareBusy(false); }
    };
    /* rename a folder (any folder, pieces.json ones included): kept as a name override in the saved state */
    const [folderNames, setFolderNames] = reactExports.useState({});
    const renameFolder = (id, title) => setFolderNames((m) => ({ ...m, [id]: title }));
    const named = (f) => (folderNames[f.id] ? { ...f, title: folderNames[f.id] } : f);
    /* deleting a folder: one made on the page leaves the list; a pieces.json folder is marked gone (its
       published pieces are data and stay in the file, but nothing on the page reaches them any more).
       Either way the drafts worked on in it go with it. No confirmation, by the reader's ruling. */
    const [goneFolders, setGoneFolders] = reactExports.useState([]);
    const goneFoldersRef = reactExports.useRef(goneFolders);
    goneFoldersRef.current = goneFolders;
    const deleteFolder = (id) => {
        if (ownFolders.some((f) => f.id === id))
            setOwnFolders((fs) => fs.filter((f) => f.id !== id));
        else setGoneFolders((g) => (g.includes(id) ? g : [...g, id]));
        setWork((w) => (w ? w.filter((wp) => wp.folder !== id || wp.published) : w));
    };
    /* opening a folder: one with nothing published in it (a folder made on the page) opens in draft mode,
       with a new piece if it holds no drafts yet; the others open for reading */
    const openFolder = (id) => {
        /* one shelf: a folder with anything in it (archive pieces or work in progress) opens for
           reading; only an empty folder drops straight into writing */
        if (
            PIECES.some((p) => folderOf(p) === id) ||
            (workRef.current ?? []).some((wp) => wp.folder === id)
        ) {
            // the mode follows you from folder to folder (the toggle is what changes it)
            if (modePrefRef.current === 'draft') enterDraft(id);
            else openView(id);
            return;
        }
        enterDraft(id);
        modePrefRef.current = 'draft'; // a fresh folder opens in draft: that is now the chosen mode
        addDraft(id);
    };
    const folderCount = (id) =>
        PIECES.filter((p) => folderOf(p) === id).length +
        (work ?? []).filter((wp) => wp.folder === id && !wp.published).length;
    const [work, rawSetWork] = reactExports.useState(null);
    /* the owning model: workRef is the single source of truth for the pieces. Every writer is evaluated
       synchronously against it and the result is published to React as a value, so a queued updater can
       neither reorder nor be overwritten, and readers of workRef never lag a render behind. cpRev counts
       every mutation (nothing reads it yet). */
    const workRef = reactExports.useRef(null);
    const cpRev = reactExports.useRef(0);
    const setWork = (u) => {
        const prev = workRef.current;
        const next = typeof u === 'function' ? u(prev) : u;
        workRef.current = next;
        cpRev.current += 1;
        rawSetWork(next);
    };
    const [lh, setLh] = reactExports.useState(1.42);
    const [hz, setHz] = reactExports.useState(0);
    const [hzEff, setHzEff] = reactExports.useState(0); // what this window shows; never saved, never synced
    const [fitRev, setFitRev] = reactExports.useState(0); // bumps on resize
    const [bg, setBg] = reactExports.useState('');
    const [palettePages, setPalettePages] = reactExports.useState({});
    const colourPage = view === 'instinct' ? 'instinct/' + (instinctNavigation?.folder || 'home') : view.startsWith('admin') ? view : 'owner';
    const palette = palettePages[colourPage] || (colourPage === 'owner' && (palettePages.home || palettePages[view])) || EMPTY_PALETTE;
    const setPalette = value => setPalettePages(previous => ({ ...previous, [colourPage]: cleanPalette(value) }));
    const [eraId, setEraId] = reactExports.useState(ERAS[2].id);
    const [soundOn, setSoundOn] = reactExports.useState(true);
    const [overlay, setOverlay] = reactExports.useState(null);
    const scrollerRef = reactExports.useRef(null);
    const colorRef = reactExports.useRef(null);
    const fileRef = reactExports.useRef(null);
    const editRefs = reactExports.useRef(new Map());
    const [platen, setPlaten] = reactExports.useState(false);
    const [activeId, setActiveId] = reactExports.useState(null);
    const [pieceLayouts, setPieceLayouts] = reactExports.useState({});
    const layoutContextRef = reactExports.useRef(null);
    const [presetCarryId, setPresetCarryId] = reactExports.useState(null); // session-only: the piece opened this draft session
    const markLayoutContext = (id) => { if (id) layoutContextRef.current = id; setActiveId(id); };
    const firstOpenDraftId = (w, v, o) => (w ?? []).filter((p) => p.folder === v).find((p) => o[p.id] !== false)?.id ?? null;
    reactExports.useEffect(() => { layoutContextRef.current = null; setActiveId(null); setPresetCarryId(mode === 'draft' ? firstOpenDraftId(work, view, open) : null); }, [view, mode]);
    const [logoRoaming, setLogoRoaming] = reactExports.useState(LOGO_ROAMING);
    const [ctlOpen, setCtlOpen] = reactExports.useState(null);
    reactExports.useEffect(() => {
        // a smaller window (rotation, resize) lifts the line it shows; the saved horizon is left alone
        const fit = () => setFitRev((v) => v + 1);
        window.addEventListener('resize', fit);
        return () => window.removeEventListener('resize', fit);
    }, []);
    const platenFollowRef = reactExports.useRef(() => {}); // the latest platenFollow, for effects declared before it
    const glideRef = reactExports.useRef({ id: 0, from: 0, to: 0, t0: 0, ms: 0 });
    const [focusDim, setFocusDim] = reactExports.useState(true); // focus dim: all but the paragraph being written fades (on by default; the toggle's choice is saved)
    const [, setDoorRev] = reactExports.useState(0); // bumps when the public face set lands, so the shelf re-reads it
    reactExports.useEffect(() => {
        const h = () => setDoorRev((v) => v + 1);
        window.addEventListener('door-faces', h);
        return () => window.removeEventListener('door-faces', h);
    }, []);
    const [bodyFace, setBodyFace] = reactExports.useState('eb-garamond');
    const [titleFace, setTitleFace] = reactExports.useState('fragment-mono');
    // reading/draft layout (indent rule): one value per viewer, saved and synced with the settings like the typeface; the default sets no attribute
    const [layoutId, setLayoutId] = reactExports.useState(LAYOUT_DEFAULT);
    const stepLayout = (dir) => setLayoutId((cur) => { const i = LAYOUTS.findIndex((l) => l.id === cur); return LAYOUTS[(i + dir + LAYOUTS.length) % LAYOUTS.length].id; });
    reactExports.useEffect(() => {
        const root = document.documentElement;
        if (layoutId === LAYOUT_DEFAULT) root.removeAttribute('data-layout'); else root.setAttribute('data-layout', layoutId);
    }, [layoutId]);
    const [taste, setTaste] = reactExports.useState(null);
    const [faceOpen, setFaceOpen] = reactExports.useState(null);
    const adminTextFace = faceBySlug(adminTaste?.slot === 'body' ? adminTaste.slug : adminType.textFace) || faceBySlug('fragment-mono');
    const adminIndexFace = faceBySlug(adminTaste?.slot === 'title' ? adminTaste.slug : adminType.indexFace) || faceBySlug('fragment-mono');
    reactExports.useEffect(() => {
        if (!adminSide) return;
        void loadFace(adminTextFace, true);
        void loadFace(adminIndexFace, true);
    }, [adminSide, adminTextFace.slug, adminIndexFace.slug]);
    const adminStyle = adminSide ? {
        '--admin-text-font': adminTextFace.family,
        '--admin-index-font': adminIndexFace.family,
        '--admin-text-size': `${adminType.textPt}pt`,
        '--admin-index-size': `${adminType.indexPt}pt`,
        '--admin-text-fvs': variationSettings(adminTextFace.axes, adminType.textAxes[adminTextFace.slug]),
        '--admin-index-fvs': variationSettings(adminIndexFace.axes, adminType.indexAxes[adminIndexFace.slug]),
        '--lh': String(adminType.lh),
        '--hz': `${adminType.hz}px`,
        '--measure': `${adminType.textWidthEm}em`,
        '--shelf-measure': `${adminType.textWidthEm * adminType.textPt * 96 / 72}px`,
    } : undefined;

    const [commit, setCommit] = reactExports.useState(false);
    const [uploads, setUploads] = reactExports.useState([]);
    const [axisValues, setAxisValues] = reactExports.useState({}); // variable faces: slug -> axis tag -> value
    const soundPref = reactExports.useRef({
        on: true,
        era: ERAS[2].id,
        commit: false,
    });
    const platenRef = reactExports.useRef(false);
    platenRef.current = platen && mode === 'draft';
    // workRef is written only by setWork (the owning model above); no render-time assignment
    soundPref.current = { on: soundOn, era: eraId, commit };
    reactExports.useEffect(() => {
        document.documentElement.classList.toggle('inverted', inverted);
        storeSet('wt-invert', inverted ? '1' : '0');
    }, [inverted]);
    reactExports.useEffect(() => {
        applyGlobalLayoutVars({ fontSizePt: textPt, indexSizePt: indexPt, textWidthEm, lineHeight: lh });
    }, [textPt, indexPt, textWidthEm, lh]);
    reactExports.useEffect(() => {
        // a saved or dragged horizon never shows below the lowest safe line for this window: local clamp only
        const e = hz > hzMax() ? clampHz(hz) : hz;
        setHzEff(e);
        document.documentElement.style.setProperty('--hz', `${e}px`);
        // platen: the typing line holds on the horizon, so it rides the drag live; keep
        // following for a beat - a single frame can read the line where the drag started
        if (platenRef.current) {
            let frames = 0;
            const tick = () => {
                platenFollowRef.current();
                if (++frames < 45) requestAnimationFrame(tick);
            };
            requestAnimationFrame(tick);
        }
    }, [hz, fitRev]);
    // in the admin lane the horizon control moves the whole page: everything pinned to --hline (buttons, plus, index,
    // logo) reads --hz from :root, so the admin horizon is mirrored there and the reader's is put back on leaving
    reactExports.useEffect(() => {
        document.documentElement.style.setProperty('--hz', `${adminSide ? adminType.hz : hzEff}px`);
    }, [adminSide, adminType.hz, hzEff]);
    reactExports.useEffect(() => {
        applyPalette(palette, inverted, bg);
    }, [bg, palette, inverted]);
    reactExports.useEffect(() => {
        document.documentElement.classList.toggle('draft-mode', mode === 'draft');
    }, [mode]);
    // faces: the tasted one wins while the pointer rests on it; otherwise the chosen one
    reactExports.useEffect(() => {
        applyFacesTo(taste?.slot === 'body' ? taste.slug : bodyFace, taste?.slot === 'title' ? taste.slug : titleFace, axisValues);
    }, [bodyFace, titleFace, taste, uploads, axisValues]); // uploads: a restored own font arrives after the first paint
    /* a knob turning: set the face's variations straight on the page, in each slot that shows it (no React render) */
    const axisLive = (slug, values) => {
        const f = faceBySlug(slug);
        if (!f) return;
        const shownBody = taste?.slot === 'body' ? taste.slug : bodyFace;
        const shownTitle = taste?.slot === 'title' ? taste.slug : titleFace;
        if (shownBody === slug)
            document.documentElement.style.setProperty(
                '--fvs-body',
                variationSettings(f.axes, values),
            );
        if (shownTitle === slug)
            document.documentElement.style.setProperty(
                '--fvs-mono',
                variationSettings(f.axes, values),
            );
    };
    /* a knob let go: keep the values (saved and synced with the settings) */
    const axisKeep = (slug, values) => setAxisValues((prev) => ({ ...prev, [slug]: values }));
    const globalLayoutValues = { fontSizePt: textPt, indexSizePt: indexPt, textWidthEm, lineHeight: lh, horizon: hz, textFace: bodyFace, titleFace, faceAxes: axisValues, layout: layoutId };
    /* the presentation snapshot sealed into a share link: the profile's appearance values
       as they stand NOW (plus this page's palette, background, invert, focus and logo
       motion), and the piece's own layout lanes - both devices when the profile stores
       both. cleanPresentation bounds every value before it can cross into a payload;
       nothing account-shaped (ids beyond the shared pieces', email, token) ever goes in. */
    const capturePresentation = (pieceId) => cleanPresentation({
        v: 1,
        global: {
            ...globalLayoutValues,
            palette: cleanPalette(palette),
            background: bg,
            inverted, focusDim, logoRoaming,
        },
        piece: pieceId && pieceLayouts[pieceId]
            ? { desktop: pieceLayouts[pieceId].desktop, mobile: pieceLayouts[pieceId].mobile }
            : undefined,
    });
    // Field rails keep their focused/last-edited context; the preset button is stricter and only follows the open draft.
    const layoutContextId = mode === 'draft' ? (activeId ?? layoutContextRef.current) : null;
    const presetContextId = mode === 'draft' ? presetCarryId : null;
    const contextPieceLayout = layoutContextId ? pieceLayouts[layoutContextId]?.[device] : null;
    const presetPieceLayout = presetContextId ? pieceLayouts[presetContextId]?.[device] : null;
    const setPieceLayoutField = (key, value) => {
        if (mode !== 'draft' || !layoutContextId) return false;
        setPieceLayouts((previous) => {
            const current = previous[layoutContextId]?.[device] ?? {};
            const base = current[key] ?? globalLayoutValues[key];
            const nextValue = typeof value === 'function' ? value(base) : value;
            return withPieceLayoutField(previous, layoutContextId, device, key, nextValue);
        });
        return true;
    };
    const setPresetLayoutField = (key, value) => {
        if (!presetContextId) return false;
        setPieceLayouts((previous) => {
            const current = previous[presetContextId]?.[device] ?? {};
            const base = current[key] ?? globalLayoutValues[key];
            const nextValue = typeof value === 'function' ? value(base) : value;
            return withPieceLayoutField(previous, presetContextId, device, key, nextValue);
        });
        return true;
    };
    const bindLayoutField = (key, globalSet) => (value) => {
        if (!setPieceLayoutField(key, value)) globalSet(value);
    };
    const clearPresetLayoutField = (key) => {
        if (!presetContextId) return false;
        setPieceLayouts((previous) => {
            const lanes = { ...(previous?.[presetContextId] ?? {}) };
            const current = { ...(lanes[device] ?? {}) };
            delete current[key];
            if (Object.keys(current).length) lanes[device] = current; else delete lanes[device];
            const next = { ...(previous ?? {}) };
            if (Object.keys(lanes).length) next[presetContextId] = lanes; else delete next[presetContextId];
            return cleanPieceLayouts(next);
        });
        return true;
    };
    const stepLayoutBound = (dir) => {
        const current = presetPieceLayout?.layout ?? layoutId;
        const i = LAYOUTS.findIndex((l) => l.id === current);
        const next = LAYOUTS[(i + dir + LAYOUTS.length) % LAYOUTS.length].id;
        if (presetContextId) {
            if (next === layoutId) clearPresetLayoutField('layout');
            else setPresetLayoutField('layout', next);
            return;
        }
        stepLayout(dir);
    };
    const previewLayout = (pid) => {
        const root = document.documentElement;
        if (presetContextId) {
            const story = document.getElementById(presetContextId);
            if (!story) return;
            const committed = presetPieceLayout?.layout;
            const use = pid ?? committed;
            if (use) story.setAttribute('data-layout', use); else story.removeAttribute('data-layout');
            return;
        }
        const use = pid ?? layoutId;
        if (use === LAYOUT_DEFAULT) root.removeAttribute('data-layout'); else root.setAttribute('data-layout', use);
    };
    const bindAxis = (slug, values) => {
        if (mode === 'draft' && layoutContextId) {
            const currentAxes = contextPieceLayout?.faceAxes ?? axisValues;
            setPieceLayoutField('faceAxes', { ...currentAxes, [slug]: values });
        } else axisKeep(slug, values);
    };
    const rail = {
        textPt: contextPieceLayout?.fontSizePt ?? textPt,
        indexPt: contextPieceLayout?.indexSizePt ?? indexPt,
        textWidthEm: contextPieceLayout?.textWidthEm ?? textWidthEm,
        lh: contextPieceLayout?.lineHeight ?? lh,
        hz: contextPieceLayout?.horizon ?? hz,
        bodyFace: contextPieceLayout?.textFace ?? bodyFace,
        titleFace: contextPieceLayout?.titleFace ?? titleFace,
        axisValues: contextPieceLayout?.faceAxes ?? axisValues,
    };
    const resetPieceLayout = () => {
        if (!presetContextId) return;
        setPieceLayouts((previous) => withoutPieceLayoutLane(previous, presetContextId, device));
    };
    const pieceLayoutStyle = (id, draftScoped = false) => {
        const override = pieceLayouts[id]?.[device];
        if (!override || (draftScoped && id !== layoutContextId)) return undefined;
        return pieceLayoutStyleOf(effectivePieceLayout(pieceLayouts, layoutProfiles.current, id, device, globalLayoutValues));
    };
    reactExports.useEffect(() => {
        for (const lanes of Object.values(pieceLayouts)) {
            const override = lanes[device];
            if (!override) continue;
            const text = faceBySlug(override.textFace), title = faceBySlug(override.titleFace);
            if (text) void loadFace(text, true);
            if (title) void loadFace(title, true);
        }
    }, [pieceLayouts, device, uploads]);
    // Mobile heads may include version rows. The first text baseline, not a guessed head height, owns the horizon.
    reactExports.useLayoutEffect(() => {
        const root = document.documentElement;
        const measure = () => {
            if (device !== 'mobile' || adminSide || view === 'home' || (view === 'instinct' && !instinctNavigation?.folder)) { root.style.setProperty('--mobile-head-correction', '0px'); return; }
            const story = document.querySelector('.page .story');
            const first = story?.querySelector('.story-text > :first-child');
            if (!first) { root.style.setProperty('--mobile-head-correction', '0px'); return; }
            // Resolve calc() head through a probe, not parseFloat of a formula.
            const probe = document.createElement('span'); probe.style.cssText = 'position:absolute;height:calc(var(--hline) - var(--pin));visibility:hidden';
            document.body.append(probe); const expected = probe.getBoundingClientRect().height; probe.remove();
            // The baseline is measured in a hidden twin block outside the editable that copies the first block's typography; nothing is inserted into the editable.
            const cs = getComputedStyle(first);
            const twin = document.createElement(first.tagName.toLowerCase()); twin.setAttribute('aria-hidden', 'true');
            twin.style.cssText = 'position:absolute;left:-99999px;top:0;visibility:hidden;pointer-events:none;margin:0;padding:0;border:0;width:' + first.clientWidth + 'px;font:' + cs.font + ';line-height:' + cs.lineHeight + ';letter-spacing:' + cs.letterSpacing + ';word-spacing:' + cs.wordSpacing + ';text-transform:' + cs.textTransform + ';font-feature-settings:' + cs.fontFeatureSettings + ';font-variation-settings:' + cs.fontVariationSettings + ';font-kerning:' + cs.fontKerning + ';text-indent:' + cs.textIndent + ';white-space:' + cs.whiteSpace;
            const mark = document.createElement('span'); mark.style.cssText = 'display:inline-block;width:0;height:0;padding:0;margin:0';
            twin.append(mark); document.body.append(twin);
            const inLine = mark.getBoundingClientRect().top - twin.getBoundingClientRect().top; twin.remove();
            const fr = first.getBoundingClientRect();
            const actual = fr.top + parseFloat(cs.borderTopWidth) + parseFloat(cs.paddingTop) + inLine - story.getBoundingClientRect().top;
            root.style.setProperty('--mobile-head-correction', `${actual - expected}px`);
        };
        measure();
        const observer = new ResizeObserver(measure); const story = document.querySelector('.page .story');
        if (story) observer.observe(story);
        document.fonts.ready.then(measure);
        window.addEventListener('resize', measure);
        return () => { observer.disconnect(); window.removeEventListener('resize', measure); };
    }, [device, view, mode, work, textPt, indexPt, lh, bodyFace, titleFace, instinctNavigation, adminSide]);
    // Ghost controls share their 1800ms activity gate with automatic writing focus.
    useChromeAwake(scrollerRef, [view, mode]);
    // when embedded, keep wheel deltas at the scroller edges from scrolling the host page
    reactExports.useEffect(() => {
        const sc = scrollerRef.current;
        if (!sc) return;
        const atEdge = (dy) => {
            const max = sc.scrollHeight - sc.clientHeight;
            return (sc.scrollTop <= 0 && dy < 0) || (sc.scrollTop >= max - 1 && dy > 0);
        };
        /* a nested scroller under the pointer takes the delta itself; the edge guard is
           only for deltas that would reach the host page (the code editor's text lives
           in one - a page at its edge must not pin it, 27 Sep: the editor would not scroll) */
        const nestedTakes = (t, dy) => {
            for (let el = t && t.nodeType === 1 ? t : t && t.parentElement; el && el !== sc; el = el.parentElement) {
                const oy = getComputedStyle(el).overflowY;
                if (oy !== 'auto' && oy !== 'scroll') continue;
                const max = el.scrollHeight - el.clientHeight;
                if (max <= 1) continue;
                if ((dy < 0 && el.scrollTop > 0) || (dy > 0 && el.scrollTop < max - 1)) return true;
            }
            return false;
        };
        const onWheel = (e) => {
            if (atEdge(e.deltaY) && !nestedTakes(e.target, e.deltaY)) e.preventDefault();
        };
        const scrollKeys = {
            ArrowDown: 40,
            ArrowUp: -40,
            PageDown: 600,
            PageUp: -600,
            ' ': 600,
            End: 1e9,
            Home: -1e9,
        };
        const onKey = (e) => {
            const t = e.target;
            /* keys pressed inside a text field are the field's own (typing and its scrolling) */
            if (t && t.closest('.editable, .io-panel, textarea, input, select, [contenteditable]')) return;
            const dy = scrollKeys[e.key];
            if (dy && atEdge(dy)) e.preventDefault();
        };
        let lastTouchY = null;
        const onTouchStart = (e) => {
            lastTouchY = e.touches[0]?.clientY ?? null;
        };
        const onTouchMove = (e) => {
            const y = e.touches[0]?.clientY;
            if (y == null || lastTouchY == null) return;
            const dy = lastTouchY - y;
            if (atEdge(dy) && !nestedTakes(e.target, dy)) e.preventDefault();
            lastTouchY = y;
        };
        window.addEventListener('wheel', onWheel, { passive: false });
        window.addEventListener('keydown', onKey);
        window.addEventListener('touchstart', onTouchStart, { passive: true });
        window.addEventListener('touchmove', onTouchMove, { passive: false });
        return () => {
            window.removeEventListener('wheel', onWheel);
            window.removeEventListener('keydown', onKey);
            window.removeEventListener('touchstart', onTouchStart);
            window.removeEventListener('touchmove', onTouchMove);
        };
    }, []);
    /* when framed, keep the host page pinned so its own scroll range never shows around the frame.
       (in the Instinct viewer this also read a viewport message; the mirror leaves that listener inert) */
    reactExports.useEffect(() => {
        if (window === window.parent) return;
        const sentinel = document.createElement('div');
        sentinel.setAttribute('aria-hidden', 'true');
        sentinel.style.cssText =
            'position:absolute;left:0;bottom:0;width:1px;height:1px;pointer-events:none;opacity:0';
        document.body.appendChild(sentinel);
        let raf = 0;
        const pin = () => {
            window.cancelAnimationFrame(raf);
            raf = window.requestAnimationFrame(() => {
                const sc = scrollerRef.current;
                const keep = sc ? sc.scrollTop : 0;
                try {
                    sentinel.scrollIntoView({ block: 'end', inline: 'nearest' });
                } catch {
                }
                if (sc && sc.scrollTop !== keep) sc.scrollTop = keep;
            });
        };
        const onMsg = (e) => {
            const m = e.data;
            if (e.source !== window.parent || !m || true) return;
        };
        window.addEventListener('message', onMsg);
        window.addEventListener('resize', pin);
        const timers = [0, 250, 800, 1600, 3000, 6000].map((t) => window.setTimeout(pin, t));
        return () => {
            window.removeEventListener('message', onMsg);
            window.removeEventListener('resize', pin);
            timers.forEach((t) => window.clearTimeout(t));
            window.cancelAnimationFrame(raf);
            sentinel.remove();
        };
    }, []);
    // platen: the line being typed holds on the horizon - the line where a piece's text begins, right
    // under its sticky head (the same line the folder list sits on) - and the page rolls under it.
    // Steady by construction: the caret is snapped to its paragraph's line grid, so glyph height,
    // empty lines and wraps can't nudge the target, and the roll is instant (no easing to wobble).
    const platenFollow = () => {
        const sc = scrollerRef.current;
        const sel = window.getSelection();
        if (!sc || !sel || !sel.rangeCount) return;
        const r = sel.getRangeAt(0);
        // the platen follows the caret, never a selection: scrolling mid-drag fights the pointer,
        // and each scroll kills the style palette before its rest is up
        if (!r.collapsed) return;
        const host =
            r.startContainer.nodeType === 1 ? r.startContainer : r.startContainer.parentElement;
        const body = host?.closest('.story-text.editable');
        if (!host || !body) return;
        // the caret's paragraph (a direct child of the body); an empty body counts as its own paragraph
        let para = host;
        while (para.parentElement && para.parentElement !== body && para !== body)
            para = para.parentElement;
        const line = parseFloat(getComputedStyle(body).lineHeight) || 30;
        const pTop = para.getBoundingClientRect().top;
        const rect = r.getClientRects()[0];
        const mid = rect && rect.height ? rect.top + rect.height / 2 : pTop + line / 2;
        const lineTop = pTop + Math.max(0, Math.floor((mid - pTop) / line)) * line;
        // the horizon: where this piece's first text line sits under its head when the head is pinned
        // (the story starts at the pin line; its first text line sits this far below the story's top -
        // zero on a wide screen where the head stands beside the text, head + gap on a phone). Both
        // scroll together, so the distance is layout, not scroll, and the target never drifts.
        const story = body.closest('.story');
        const first = body.firstElementChild ?? body;
        const pin = parseFloat(getComputedStyle(document.querySelector('.page')).paddingTop) || 0;
        const horizon =
            pin +
            (story ? first.getBoundingClientRect().top - story.getBoundingClientRect().top : 0);
        // sub-pixel: line heights are fractional, so rounding each roll would let a pixel of error creep in
        const delta = lineTop - horizon;
        if (Math.abs(delta) < 0.5) return;
        /* a keystroke's one-line roll stays instant - it must not lag behind the typing.
           A leap between paragraphs glides instead of snapping, like butter: one cubic
           curve from here to there, soft at both ends, longer for longer ways. A new
           target mid-glide starts its curve where the page already is, so the softness
           never breaks; his own scroll ends the glide at once (below) */
        const leap = Math.abs(delta) > line * 1.6;
        const g = glideRef.current;
        if (!leap) {
            if (g.id) cancelAnimationFrame(g.id);
            g.id = 0;
            sc.scrollTop += delta;
            return;
        }
        g.from = sc.scrollTop;
        g.to = sc.scrollTop + delta;
        g.t0 = performance.now();
        g.ms = Math.min(850, Math.max(280, 280 + Math.abs(g.to - g.from) * 0.55));
        if (g.id) return; // already gliding: the running frame picks up the new curve
        const ease = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
        const step = (now) => {
            const t = Math.min(1, (now - g.t0) / g.ms);
            sc.scrollTop = g.from + (g.to - g.from) * ease(t);
            if (t >= 1) {
                g.id = 0;
                return;
            }
            g.id = requestAnimationFrame(step);
        };
        g.id = requestAnimationFrame(step);
    };
    platenFollowRef.current = platenFollow;
    reactExports.useEffect(() => {
        document.documentElement.classList.toggle('platen', platen && mode === 'draft');
        if (!(platen && mode === 'draft')) return;
        let raf = 0;
        const onSel = () => {
            window.cancelAnimationFrame(raf);
            raf = window.requestAnimationFrame(platenFollow);
        };
        // his own scroll ends the glide at once: the page must never pull against the hand
        const stopGlide = () => {
            const g = glideRef.current;
            if (g.id) cancelAnimationFrame(g.id);
            g.id = 0;
        };
        const sc = scrollerRef.current;
        sc?.addEventListener('wheel', stopGlide, { passive: true });
        sc?.addEventListener('touchmove', stopGlide, { passive: true });
        document.addEventListener('selectionchange', onSel);
        onSel();
        return () => {
            document.removeEventListener('selectionchange', onSel);
            sc?.removeEventListener('wheel', stopGlide);
            sc?.removeEventListener('touchmove', stopGlide);
            stopGlide();
            window.cancelAnimationFrame(raf);
        };
    }, [platen, mode]);
    // the paragraph holding the caret is marked data-focus (always, in draft: an empty line keeps
    // its height only under the caret); with focus dim on, CSS fades the rest of the page
    reactExports.useEffect(() => {
        if (mode !== 'draft') return;
        const on = focusDim;
        document.documentElement.classList.toggle('focusdim', on);
        let current = null;
        const mark = () => {
            const sel = window.getSelection();
            const n = sel && sel.rangeCount ? sel.getRangeAt(0).startContainer : null;
            const el = n ? (n.nodeType === 1 ? n : n.parentElement) : null;
            const body = el?.closest('.story-text.editable');
            // the paragraph: the body's child that holds the caret
            let para = el;
            while (para && body && para.parentElement !== body) para = para.parentElement;
            const next = body && para && para.parentElement === body ? para : null;
            if (next === current) return;
            current?.removeAttribute('data-focus');
            next?.setAttribute('data-focus', '');
            current = next;
            document.documentElement.classList.toggle('focus-in', on && !!next);
        };
        document.addEventListener('selectionchange', mark);
        mark();
        return () => {
            document.removeEventListener('selectionchange', mark);
            current?.removeAttribute('data-focus');
            document.documentElement.classList.remove('focusdim', 'focus-in');
        };
    }, [focusDim, mode]);
    reactExports.useEffect(() => {
        document.documentElement.classList.toggle('commit', commit && mode === 'draft');
    }, [commit, mode]);
    // audio: wake the engine on the first gesture so the first keystroke is not the one paying for startup
    reactExports.useEffect(() => {
        if (mode !== 'draft') return;
        const warm = () => warmAudio();
        window.addEventListener('pointerdown', warm, { passive: true });
        window.addEventListener('keydown', warm);
        const t = window.setTimeout(() => calibrateSound(), 400);
        return () => {
            window.removeEventListener('pointerdown', warm);
            window.removeEventListener('keydown', warm);
            window.clearTimeout(t);
        };
    }, [mode]);
    const register = (id, part, el) => {
        const cur = editRefs.current.get(id) ?? { title: null, text: null };
        cur[part] = el;
        editRefs.current.set(id, cur);
        if (part === 'text' && el) el.__dictationTarget = () => {
            const current = workRef.current?.find(p => p.id === id);
            const version = current?.versions?.[current.current];
            return el.isConnected && editRefs.current.get(id)?.text === el && version?.vid
                ? { pieceId: id, versionId: version.vid } : null;
        };
        attachTypeSound(el, soundPref);
        attachCommit(el, soundPref);
    };
    const harvestPiece = (wp) => {
        const r = editRefs.current.get(wp.id);
        if (!r?.text || !r.title) return wp;
        const title = readTitle(r.title);
        const lines = readParas(r.text);
        const cur = wp.versions[wp.current];
        if (title === cur.title && sameLines(lines, cur.lines)) return wp;
        if (cur.original) return wp; // originals never absorb edits; the first keystroke spawns a version instead
        const snaps = withSnap(cur, Date.now());
        return {
            ...wp,
            versions: wp.versions.map((v, i) =>
                i === wp.current ? { ...v, title, lines, ...(snaps ? { snaps } : {}) } : v,
            ),
        };
    };
    const harvestAll = (w) => w.map(harvestPiece);
    /* fold / unfold a piece. Folding while reading inside it (its title pinned at the top) would collapse
       the text out from under the view and drop the reader somewhere further down the archive. So the view
       first steps back to the piece's own start, putting its title where the pinned title was, and then
       the piece closes: the reader stays level with the closed piece. */
    const toggleFold = (id) => {
        const sc = scrollerRef.current;
        const section = document.getElementById(id);
        const head = section?.querySelector('.story-head');
        if (open[id] && sc && section && head) {
            const pinY = head.getBoundingClientRect().top; // where the title sits now (pinned, or natural)
            const naturalY = section.getBoundingClientRect().top; // where it sits when not pinned: the piece's top edge
            if (naturalY < pinY - 1) sc.scrollTop -= pinY - naturalY;
        }
        setOpen((prev) => ({ ...prev, [id]: !prev[id] }));
    };
    const toggleDraftFold = (id) => {
        setPresetCarryId((cur) => open[id] ? (cur === id ? null : cur) : id);
        toggleFold(id);
    };
    /* long press (550ms, the hold the story titles use) on the index dot: every title in this view folds,
       or, when all are already folded, unfolds. A held press is not a click: the index stays as it was. */
    const dotHold = reactExports.useRef(undefined);
    const dotHeld = reactExports.useRef(false);
    const dotXY = reactExports.useRef(null);
    const foldAll = () => {
        const ids = [...document.querySelectorAll('section.story[id]')].map((s) => s.id);
        if (!ids.length) return;
        if (view === 'instinct') {
            const folds = uiPresets.instinctViewer.folds;
            const allFolded = ids.every((id) => folds[id] === false);
            ids.forEach((id) => changeInstinctFold(id, allFolded));
            return;
        }
        const allFolded = ids.every((id) => !open[id]);
        setOpen((prev) => ({ ...prev, ...Object.fromEntries(ids.map((id) => [id, allFolded])) }));
        if (!allFolded && scrollerRef.current) scrollerRef.current.scrollTop = 0;
    };
    const foldAllRef = reactExports.useRef(foldAll);
    foldAllRef.current = foldAll;
    reactExports.useEffect(() => () => window.clearTimeout(dotHold.current), []);
    reactExports.useEffect(() => {
        void restoreFonts().then(setUploads);
    }, []);
    /* a device just joined: bring in what the code already holds, else send up what this device has */
    const syncJoined = () => {
        // A new joined credential must be checked even if its archive is unavailable.
        setShelfRev((n) => n + 1);
        /* Restore archive and state off the login click's critical path. Pull
           first: never let a provisional empty shelf overwrite a remote copy. */
        syncLoading.current = true;
        const restoringToken = token();
        adminCustodyPending.current=[];adminCustodyDirty.current=false;adminProfilesRemote.current=undefined;adminProfilesBinding.current=null;adminProfilesHeld.current=false;adminProfiles.current={};setAdminType({...adminDefaults(),deviceLane:deviceRef.current});
        setUiPresets(cleanUiPresets(null));
        void Promise.all([pull(), loadPrivate()]).then(([r, loaded]) => {
            if (token() !== restoringToken) return;
            if (loaded) acceptArchive(restoringToken);
            if (r) applyRemote(r);
            if (loaded) setShelfRev((n) => n + 1);
            syncLoading.current = false;
            // Failed reads never bootstrap a provisional shelf back to the server.
        }).catch(() => { syncLoading.current = false; });
        void shareLocalFonts().then((f) => setUploads(f));
    };
    // the shelf can change under the page (joining, a new code): a bump makes the page read it again
    const [shelfRev, setShelfRev] = reactExports.useState(0);
    // The current joined bucket must be the worker's admin bucket. A saved token alone is not proof.
    reactExports.useEffect(() => {
        const current = token();
        if (!current) { adminVerifiedBinding.current=null;setAdminVerified(false); return; }
        const probeAttempt = currentAttempt(); // captured at probe start; the write lands only if this attempt is still current
        // Fail closed while unavailable; retry without clearing the saved credential.
        adminVerifiedBinding.current=null;
        setAdminVerified(false);
        return startAdminProbe({ token, current,
            request: signal => fetch(`${SYNC_URL}/repo/drafts`, {
                headers: { Authorization: `Bearer ${current}` }, signal, cache: 'no-store'
            }),
            onResult: ({ allowed, revoked, status }) => {
                noteAdminProbe(probeAttempt, current, String(status));
                if (allowed) localStorage.setItem(ADMIN_TOKEN_KEY, current);
                else if (revoked) localStorage.removeItem(ADMIN_TOKEN_KEY);
                adminVerifiedBinding.current=allowed?current:null;
                setAdminVerified(allowed);
                setAdminSession(n => n + 1);
            },
            onError: () => {
                noteAdminProbe(probeAttempt, current, 'network-error');
                adminVerifiedBinding.current=null;setAdminVerified(false);
            }
        });
    }, [shelfRev]);
    reactExports.useEffect(() => {
        if (mode !== 'draft' || !adminVerified) return;
        const current = token();
        if (!current) return;
        let canceled = false;
        let stopMount = null;
        let probeBudget = null;
        const probeScope = localStorage.getItem('middots-sync-base-scope') || 'unknown-profile';
        import('./admin-transcribe-budget.js?v=20261027-f7-held-keys-r1').then((m) => {
            if (canceled || token() !== current) return null;
            probeBudget = m.createRequestBudget({ scope: probeScope });
            return probeBudget.reserve('other').then(() => {
                if (canceled || token() !== current || (localStorage.getItem('middots-sync-base-scope') || 'unknown-profile') !== probeScope) return null;
                return fetch(`${SYNC_URL}/api/transcribe/v1/counters`, { headers: { Authorization: `Bearer ${current}` } });
            });
        })
            .then((r) => (r?.ok ? import('./transcribe-mount.js?v=20261027-f7-held-keys-r1') : null))
            .then((m) => {
                if (canceled || !m || token() !== current) return;
                stopMount = m.startTranscribeMount({ syncUrl: SYNC_URL, getToken: token, sound: () => soundPref.current });
            })
            .catch(() => {});
        return () => { canceled = true; probeBudget?.stop(); if (stopMount) stopMount(); };
    }, [adminVerified, mode]);
    const syncRekeyed = async () => {
        setShelfRev((n) => n + 1);
        const restoringToken = token();
        const [r, loaded] = await Promise.all([pull(), loadPrivate()]);
        if (token() !== restoringToken) return;
        if (loaded) acceptArchive(restoringToken);
        if (r) applyRemote(r);
    };
    const uploadFace = async (file) => {
        const face = await addFontFile(file, { share: preferenceLane.current !== 'instinct', namespace: preferenceLane.current === 'instinct' ? 'instinct' : '' });
        setUploads([...UPLOADED]);
        return face;
    };
    const isFontFile = (f) => /\.(woff2?|ttf|otf)$/i.test(f.name) || /^font\//.test(f.type);
    reactExports.useEffect(() => {
        const carriesFiles = (e) => !!e.dataTransfer && [...e.dataTransfer.types].includes('Files');
        let depth = 0; // dragenter/leave fire per element; count them so the hint doesn't flicker
        const hint = (on) => document.documentElement.classList.toggle('font-dropping', on);
        const onEnter = (e) => {
            if (!carriesFiles(e)) return;
            depth++;
            hint(true);
        };
        const onLeave = (e) => {
            if (!carriesFiles(e)) return;
            depth = Math.max(0, depth - 1);
            if (!depth) hint(false);
        };
        const onOver = (e) => {
            if (carriesFiles(e)) e.preventDefault();
        };
        const onDrop = (e) => {
            depth = 0;
            hint(false);
            const files = [...(e.dataTransfer?.files ?? [])].filter(isFontFile);
            if (!carriesFiles(e)) return;
            e.preventDefault(); // never let the browser open the file instead
            void (async () => {
                let last = null;
                for (const f of files) {
                    try {
                        last = await addFontFile(f, { share: preferenceLane.current !== 'instinct', namespace: preferenceLane.current === 'instinct' ? 'instinct' : '' });
                    } catch {
                    }
                }
                setUploads([...UPLOADED]);
                if (last) {
                    if (adminSide) updateAdminType('textFace', last.slug);
                    else setBodyFace(last.slug);
                } // the (last) dropped font is the text face now
            })();
        };
        window.addEventListener('dragenter', onEnter);
        window.addEventListener('dragleave', onLeave);
        window.addEventListener('dragover', onOver);
        window.addEventListener('drop', onDrop);
        return () => {
            window.removeEventListener('dragenter', onEnter);
            window.removeEventListener('dragleave', onLeave);
            window.removeEventListener('dragover', onOver);
            window.removeEventListener('drop', onDrop);
        };
    }, [adminSide]);
    const dropFace = (slug) => {
        // Owner uploads stay readable here, but only bridge-local uploads can be removed here.
        if (preferenceLane.current === 'instinct' &&
            (!faceBySlug(slug)?.localOnly || [ownerSettings.current?.textFace, ownerSettings.current?.titleFace].includes(slug))) return;
        void removeFont(slug, { share: preferenceLane.current !== 'instinct', namespace: preferenceLane.current === 'instinct' ? 'instinct' : '' }).finally(() => setUploads([...UPLOADED]));
        setAxisValues((prev) => {
            const { [slug]: _gone, ...rest } = prev;
            return rest;
        });
        if (bodyFace === slug) setBodyFace('eb-garamond');
        if (titleFace === slug) setTitleFace('fragment-mono');
    };
    // view <-> address: #/<folder> for a folder, no hash for the main page
    reactExports.useEffect(() => {
        const want = view === 'home' ? '' : `#/${view}`;
        if (location.hash !== want)
            history.pushState(null, '', want || location.pathname + location.search);
    }, [view]);
    reactExports.useEffect(() => {
        const onPop = () => setView(viewFromHash(ownFoldersRef.current) ?? 'home');
        window.addEventListener('popstate', onPop);
        return () => window.removeEventListener('popstate', onPop);
    }, []);
    reactExports.useEffect(() => {
        if (view.startsWith('admin') && !adminToken()) setView('home');
        // one door, one spot: inside the admin rooms his own door stands there - the preview's steps aside
        const pd = document.getElementById('middots-door');
        if (pd) pd.style.display = view.startsWith('admin') ? 'none' : '';
    }, [view]);
    const onCover = mode === 'read' && view === 'home'; // the main page: folders only
    // the main page is never in draft mode: arriving there (back button, address) closes the drafts first
    reactExports.useEffect(() => {
        if (view === 'home' && mode === 'draft') leaveDraft();
    }, [view, mode]);
    const openView = (next) => {
        setView(next);
        scrollerRef.current?.scrollTo({ top: 0 });
    };
    /* search: the shelf as it stands - drafts in their current version once drafting has begun */
    const searchItems = () => {
        if (view === 'instinct') return instinctNavigation?.items ?? [];
        const w = workRef.current;
        const gone = goneFoldersRef.current; // a deleted folder's pieces are out of reach, search included
        // every item carries its shelf number inside its own folder (the reading index's count)
        const numbered = (items) => {
            const per = {};
            for (const it of items) (per[it.folder] ??= []).push(it);
            return items.map((it) => ({ ...it, num: per[it.folder].length - per[it.folder].indexOf(it) }));
        };
        if (w)
            return numbered(
                w
                    .filter((wp) => !gone.includes(wp.folder))
                    .map((wp) => ({
                        id: wp.id,
                        folder: wp.folder,
                        title: wp.versions[wp.current].title,
                        lines: wp.versions[wp.current].lines,
                    })),
            );
        return numbered(
            PIECES.filter((p) => !gone.includes(folderOf(p))).map((p) => ({
                id: p.id,
                folder: folderOf(p),
                title: p.title,
                lines: flatLines(p),
            })),
        );
    };
    /* a hit: open its folder and piece, then bring the matched line to the horizon and mark it */
    const goToHit = (h) => {
        if (view === 'instinct') { instinctNavigation?.goToHit(h); return; }
        if (view !== h.folder) setView(h.folder);
        setOpen((o) => ({ ...o, [h.id]: true }));
        window.setTimeout(() => {
            const sc = scrollerRef.current;
            const section = document.getElementById(h.id);
            if (!sc || !section) return;
            const target =
                h.line < 0
                    ? section.querySelector('.story-title')
                    : section.querySelectorAll('.story-text > p')[h.line];
            const el = target ?? section;
            const pin =
                parseFloat(getComputedStyle(document.querySelector('.page')).paddingTop) || 0;
            const head = section.querySelector('.story-head');
            const below = h.line < 0 || !head || window.innerWidth > 700 ? 0 : head.offsetHeight; // the phone's head sits above the text
            sc.scrollTo({
                top: Math.max(0, sc.scrollTop + el.getBoundingClientRect().top - pin - below - 24),
                behavior: 'auto',
            });
            // mark the match itself (CSS Custom Highlight API where there is one; the line otherwise)
            const reg = CSS.highlights;
            const HL = window.Highlight;
            const range = findInElement(el, h);
            if (reg && HL && range) {
                reg.set('search-hit', new HL(range));
                window.setTimeout(() => reg.delete('search-hit'), 2600);
            } else {
                el.classList.add('search-flash');
                window.setTimeout(() => el.classList.remove('search-flash'), 2600);
            }
        }, 60);
    };
    /* draft mode, inside a folder: the current one, or `into` (a folder just made). From the main page it
       opens the first folder. Only the pieces of that folder are shown (see the draft list below). */
    const enterDraft = (into) => {
        if (view === 'instinct') return;
        setWork(
            (w) =>
                w ??
                PIECES.map((p) => ({
                    id: p.id,
                    published: true,
                    versions: [
                        {
                            vid: `v-${p.id}-base`,
                            when: p.when,
                            born: p.when,
                            title: p.title,
                            lines: flatLines(p),
                            original: true,
                        },
                    ],
                    current: 0,
                    seat: 0,
                    audio: p.audio,
                    note: p.note,
                    hasEndmark: true,
                    folder: folderOf(p),
                })),
        );
        if (into) setView(into);
        else if (view === 'home' || view.startsWith('admin')) setView(FOLDERS[0].id); // drafts are worked on inside a folder
        setMode('draft');
    };
    const leaveDraft = () => {
        setWork((w) => (w ? harvestAll(w) : w));
        setMode('read');
    };
    /* a long press on empty space while drafting returns to reading - the same 550ms
       hold as everywhere else */
    const pageHold = reactExports.useRef(undefined);
    const pagePressAt = reactExports.useRef(null);
    const pagePress = (e) => {
        window.clearTimeout(pageHold.current);
        pagePressAt.current = e ? { x: e.clientX, y: e.clientY } : null;
        pageHold.current = window.setTimeout(() => {
            pagePressAt.current = null;
            modePrefRef.current = 'read';
            leaveDraft();
        }, 550);
    };
    const pageRelease = () => {
        window.clearTimeout(pageHold.current);
        pagePressAt.current = null;
    };
    // a held finger may drift this much (CSS px); past it the gesture is a scroll or drag, not a long press
    const PAGE_HOLD_MOVE_PX = 10;
    const pageMove = (e) => {
        const p = pagePressAt.current;
        if (p && (Math.abs(e.clientX - p.x) > PAGE_HOLD_MOVE_PX || Math.abs(e.clientY - p.y) > PAGE_HOLD_MOVE_PX)) pageRelease();
    };
    reactExports.useEffect(() => () => window.clearTimeout(pageHold.current), []);
    const newVid = () => `v-${Date.now()}-${randomUnit().toString(36).slice(2, 7)}`;
    // editing re-stamps the version's date and rises it to the top of its stack.
    // an original is never edited: the first keystroke on it becomes a new version carrying that edit,
    // the original stays untouched at the bottom. the live editor keeps its DOM (seat unchanged), so the caret never jumps
    const stampEdit = (id) => {
        setWork((w) => {
            if (!w) return w;
            const idx = w.findIndex((p) => p.id === id);
            if (idx < 0) return w;
            const wp = w[idx];
            const stamp = nowStamp();
            const cur = wp.versions[wp.current];
            const next = [...w];
            if (cur.original) {
                const r = editRefs.current.get(id);
                const title = r?.title ? readTitle(r.title) : cur.title;
                const lines = r?.text ? readParas(r.text) : [...cur.lines];
                const spawned = {
                    vid: newVid(),
                    when: stamp,
                    born: stamp,
                    title,
                    lines,
                };
                next[idx] = { ...wp, versions: [spawned, ...wp.versions], current: 0 };
                return next;
            }
            if (wp.current === 0 && cur.when === stamp) return w;
            const versions = [...wp.versions];
            versions[wp.current] = { ...cur, when: stamp };
            const [moved] = versions.splice(wp.current, 1);
            versions.unshift(moved);
            next[idx] = { ...wp, versions, current: 0 };
            return next;
        });
        if (platenRef.current) window.requestAnimationFrame(() => platenFollow());
    };
    /* restore a past self: it comes back as a new version on top of the stack, so the current text
       stays untouched in its own version (and keeps its own past selves) */
    const restoreSnap = (id, snap) => {
        const stamp = nowStamp();
        setWork((w) =>
            !w
                ? w
                : w.map((wp) => {
                      if (wp.id !== id) return wp;
                      const h = harvestPiece(wp);
                      const back = {
                          vid: newVid(),
                          when: stamp,
                          born: stamp,
                          title: snap.title,
                          lines: [...snap.lines],
                      };
                      return {
                          ...h,
                          versions: [back, ...h.versions],
                          current: 0,
                          seat: h.seat + 1,
                      };
                  }),
        );
    };
    const loadVersion = (id, vIdx) => {
        setWork((w) =>
            !w
                ? w
                : w.map((wp) => {
                      if (wp.id !== id || vIdx === wp.current) return wp;
                      const h = harvestPiece(wp);
                      return { ...h, current: vIdx, seat: h.seat + 1 };
                  }),
        );
    };
    /* delete one version (the wipe on that row): the piece keeps its other versions, and the neighbour
       below it (or the one above, for the last) becomes the selected one; a lone version has no x */
    const removeVersion = (id, vIdx) => {
        setWork((w) =>
            !w
                ? w
                : w.map((wp) => {
                      if (wp.id !== id || wp.versions.length < 2) return wp;
                      const h = harvestPiece(wp);
                      if (h.versions[vIdx]?.original) return wp; // an original is never deleted as a version
                      const versions = h.versions.filter((_, i) => i !== vIdx);
                      const current = vIdx < h.current ? h.current - 1 : Math.min(h.current, versions.length - 1);
                      return { ...h, versions, current, seat: h.seat + 1 };
                  }),
        );
    };
    /* delete one past self from a piece's history list */
    const removeSnap = (id, snap) => {
        setWork((w) =>
            !w
                ? w
                : w.map((wp) => {
                      if (wp.id !== id) return wp;
                      let gone = false; // exactly one entry goes, even when two snapshots share a time and title
                      const same = (s) => !gone && (s === snap || (s.t === snap.t && s.at === snap.at && s.title === snap.title)) && (gone = true);
                      return {
                          ...wp,
                          versions: wp.versions.map((v) => {
                              if (gone || !v.snaps?.some((s) => s === snap || (s.t === snap.t && s.at === snap.at && s.title === snap.title))) return v;
                              const rest = v.snaps.filter((s) => !same(s));
                              const { snaps: _gone, ...bare } = v;
                              return rest.length ? { ...bare, snaps: rest } : bare;
                          }),
                      };
                  }),
        );
    };
    /* closure control: the endmark gesture flips hasEndmark through the same immutable piece
       update every other mutation uses (map + spread, like stampEdit; no new endpoint, storage,
       key, timer, poll, or request). In-session only: makePayload drops the flag and the importer
       recomputes it, so a reload or restore rebuilds it from the piece's published state. */
    const toggleEndmark = (id) => {
        setWork((w) =>
            !w
                ? w
                : w.map((wp) => {
                      if (wp.id !== id || typeof wp.hasEndmark !== 'boolean') return wp; // invalid/missing data: unchanged
                      return { ...wp, hasEndmark: !wp.hasEndmark };
                  }),
        );
    };
    const duplicateVersion = (id) => {
        setWork((w) =>
            !w
                ? w
                : w.map((wp) => {
                      if (wp.id !== id) return wp;
                      const h = harvestPiece(wp);
                      const cur = h.versions[h.current];
                      const stamp = nowStamp();
                      return {
                          ...h,
                          versions: [
                              {
                                  vid: newVid(),
                                  when: stamp,
                                  born: stamp,
                                  title: cur.title,
                                  lines: [...cur.lines],
                              },
                              ...h.versions,
                          ],
                          current: 0,
                          seat: h.seat + 1,
                      };
                  }),
        );
    };
    const addDraft = (into) => {
        const folder = into ?? (view === 'home' || view.startsWith('admin') ? FOLDERS[0].id : view);
        const stamp = nowStamp();
        const id = `draft-${Date.now()}`;
        setPresetCarryId(id);
        setOpen((prev) => ({ ...prev, [id]: true }));
        setWork((w) => [
            {
                id,
                published: false,
                versions: [
                    {
                        vid: `v-${Date.now()}-new`,
                        when: stamp,
                        born: stamp,
                        title: '',
                        lines: [],
                    },
                ],
                current: 0,
                seat: 0,
                audio: [],
                hasEndmark: false,
                folder,
            },
            ...(w ?? []),
        ]);
        focusNewRef.current = id;
        scrollerRef.current?.scrollTo({ top: 0, behavior: 'smooth' });
    };
    /* a new piece opens ready to write: once its editor exists, the caret goes into its text */
    const focusNewRef = reactExports.useRef(null);
    reactExports.useEffect(() => {
        const id = focusNewRef.current;
        const el = id ? editRefs.current.get(id)?.text : null;
        if (!id || !el) return;
        focusNewRef.current = null;
        el.focus({ preventScroll: true });
        const range = document.createRange();
        range.selectNodeContents(el.firstElementChild ?? el);
        range.collapse(true);
        const sel = window.getSelection();
        sel?.removeAllRanges();
        sel?.addRange(range);
    }, [work]);
    const removePublished = async (id) => {
        const piece = PIECES.find((p) => p.id === id);
        if (!piece || !window.confirm(`Delete “${piece.title}” from the private archive?`)) return;
        try {
            await deletePrivate(id);
            setWork((w) => (w ? w.filter((p) => p.id !== id) : w));
            setShelfRev((n) => n + 1);
        } catch (e) {
            window.alert(e.message || 'could not delete this piece');
        }
    };
    const removeDraft = async (id) => {
        const target = (workRef.current ?? []).find((p) => p.id === id);
        if (target?.published) {
            const piece = PIECES.find((p) => p.id === id);
            if (!piece || !window.confirm(`Delete “${piece.title}” from the private archive?`)) return;
            try {
                await deletePrivate(id);
                setShelfRev((n) => n + 1);
            } catch (e) {
                window.alert(e.message || 'could not delete this piece');
                return;
            }
        }
        setWork((w) => (w ?? []).filter((p) => p.id !== id));
        editRefs.current.delete(id);
    };
    /* one shelf: reading shows the folder's pieces as they stand - the work once the bench has
       loaded, the archive list before that (and for a visitor, who only has the public list) */
    const readingList = (folder) => {
        if (work)
            return work
                .filter((wp) => wp.folder === folder)
                .map((wp) => {
                    const v = wp.versions[wp.current];
                    return {
                        id: wp.id,
                        title: v.title,
                        when: v.when,
                        blocks: v.lines,
                        runs: true,
                        history: pieceSnapshots(wp),
                        published: !!wp.published,
                        versionCount: wp.versions.length,
                        versionIndex: wp.current,
                        versionOriginal: !!wp.versions[wp.current]?.original,
                        endmark: wp.hasEndmark,
                        audio: wp.audio ?? [],
                        note: wp.note,
                        /* the mapped piece must keep its home: folderOf() defaults a missing
                           folder to unarchive, and a long press drafts the piece where it lives */
                        folder: wp.folder,
                    };
                });
        return PIECES.filter((p) => folderOf(p) === folder);
    };
    /* the draft's middot shares the piece as it stands in the editor right now - the same
       mapped shape the reading list builds, so one mint path serves both modes */
    const draftSharePiece = (wp) => {
        const v = wp.versions[wp.current];
        return { id: wp.id, title: v.title, when: v.when, blocks: v.lines };
    };
    /* the export payload: settings plus every piece with its versions. The same shape is what the mirror
       keeps in localStorage, so a saved state and an exported file restore through one path (doImport) */
    const makePayload = (harvested) => {
        return {
        kind: 'dreamwake-drafts',
        version: 4,
        layoutProfiles: layoutProfiles.current,
        pieceLayouts: payloadPieceLayouts(pieceLayouts, harvested, workRef.current),
        exported: nowStamp(),
        settings: {
            fontSizePt: textPt,
            indexSizePt: indexPt,
            textWidthEm,
            lineHeight: Math.round(lh * 100) / 100,
            background: bg || 'default',
            palettePages,
            horizon: hz,
            inverted,
            soundEra: eraId,
            sound: soundOn,
            platen,
            focusDim,
            commitment: commit,
            textFace: bodyFace,
            titleFace,
            layout: layoutId,
            faceAxes: axisValues, // knob values of variable faces: slug -> axis tag -> value
        },
        pieces:
            harvested === null
                ? null
                : harvested.map(({ id, published, versions, current, folder, audio }) => ({
                      id,
                      title: versions[current].title,
                      published,
                      folder,
                      ...(audio?.length ? { audio } : {}),
                      versions: versions.map(
                          ({ vid, when, born, title, lines, original, snaps }) => ({
                              vid,
                              when,
                              born,
                              title,
                              lines,
                              ...(original ? { original: true } : {}),
                              ...(snaps?.length ? { snaps } : {}),
                          }),
                      ),
                      current,
                  })),
        };
    };
    const exportAs = (kind, pick) => {
        setCtlOpen(null);
        const folder =
            liveFolders()
                .map(named)
                .find((f) => f.id === view)?.title ?? 'middots';
        const d = new Date();
        const day = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; // the reader's own day
        const base = `${folder} ${day}`.replace(/[\\/:*?"<>|]+/g, '-');
        if (kind === 'pdf') {
            void exportPdf(base, pick); // snapshot the clicked piece and current UI settings now
            return;
        } // after the family folds away
        const docs = collect();
        if (kind === 'txt')
            saveBytes(
                `${base}.txt`,
                new TextEncoder().encode(toTxt(docs)),
                'text/plain;charset=utf-8',
            );
        else
            saveBytes(
                `${base}.docx`,
                toDocx(docs),
                'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            );
    };
    const doExport = () => {
        const w = workRef.current;
        if (!w) return;
        const harvested = harvestAll(w);
        setWork(harvested);
        const payload = makePayload(harvested);
        setOverlay({ kind: 'export', text: JSON.stringify(payload, null, 2) });
    };
    /* restore: set when the mirror brings back its saved state on load - pieces may then be null (settings
       only), and the saved mode is reopened instead of jumping into draft */
    const doImport = makeImporter({ setLayout: setLayoutId, onLayoutImport: data => {
        layoutProfiles.current = migrateLayouts(data.layoutProfiles, data.settings, data.bridgeSettings ?? bridgeDefaults());
    }, onPieceLayoutsImport: value => setPieceLayouts(cleanPieceLayouts(value)), modePrefRef, setAxisValues, setPalettePages, setBg, setBodyFace, setCommit, setEraId, setFocusDim, setHz, setIndexPt, setInverted, setLh, setMode, setOverlay, setPlaten, setSoundOn, setTextPt, setTextWidthEm, setTitleFace, setWork });
    const [restored, setRestored] = reactExports.useState(false);
    const applySettings = makeSettingsImporter({ setLayout: setLayoutId, setAxisValues, setPalettePages, setBg, setBodyFace, setCommit, setEraId, setFocusDim, setHz, setIndexPt, setInverted, setLh, setPlaten, setSoundOn, setTextPt, setTextWidthEm, setTitleFace });
    // Device changes switch only layout values; shared documents and sound choices do not move.
    reactExports.useLayoutEffect(() => {
        if (!restored || deviceRef.current === device) return;
        const before = deviceRef.current;
        const surface = preferenceLane.current;
        const current = makePayload(null).settings;
        layoutProfiles.current ??= migrateLayouts(null, ownerSettings.current ?? current, bridgeSettings.current ?? bridgeDefaults());
        layoutProfiles.current[surface][before] = layoutOnly(current);

        deviceRef.current = device;
        switchingPreferences.current = true;
        const next = { ...current, ...layoutProfiles.current[surface][device] };
        if (surface === 'owner') ownerSettings.current = next; else bridgeSettings.current = next;
        applySettings(next);
        setAdminType({...adminDefaults(),...(adminVerified && !adminProfilesHeld.current && adminProfilesBinding.current===token()?adminProfiles.current[device]:{}),deviceLane:device});
        setCtlOpen(null); setFaceOpen(null); setTaste(null);
    }, [device, restored]);
    // Owner and Instinct settings stay separate within each responsive device lane.
    reactExports.useLayoutEffect(() => {
        if (!restored) return;
        const next = view === 'instinct' ? 'instinct' : 'owner';
        if (preferenceLane.current === next) return;
        const current = makePayload(null).settings;
        layoutProfiles.current ??= migrateLayouts(null, ownerSettings.current ?? current, bridgeSettings.current ?? bridgeDefaults());
        layoutProfiles.current[preferenceLane.current][deviceRef.current] = layoutOnly(current);
        if (next === 'instinct') {
            ownerSettings.current = current;
            bridgeSettings.current = { ...(bridgeSettings.current ?? bridgeDefaults()), ...layoutProfiles.current.instinct[deviceRef.current] };
            switchingPreferences.current = true;
            applySettings(bridgeSettings.current);
        } else {
            bridgeSettings.current = current;
            switchingPreferences.current = true;
            ownerSettings.current = { ...ownerSettings.current, ...layoutProfiles.current.owner[deviceRef.current] };
            applySettings(ownerSettings.current);
        }
        preferenceLane.current = next;
        setCtlOpen(null); setFaceOpen(null); setTaste(null);
    }, [view, restored]);
    /* ---- saved state (mirror only) ----
       On the standalone page, settings, drafts, the current mode, which pieces are unfolded and the scroll
       position survive a reload. The state is written
       as an export payload (makePayload) and read back through doImport, so it follows the same rules as an
       imported file: published originals are restored from the archive, edits live in their own versions.
       Typing does not re-render the app (the editor owns its DOM), so edits are harvested on a short pause
       after input and again when the page is hidden or closed. */
    // false until the saved state has been handed to React; nothing is written before that
    const saveStateRef = reactExports.useRef(() => {});
    const localEditEpoch = reactExports.useRef(0); // input before the harvest debounce is already newer owner work
    reactExports.useEffect(() => { localEditEpoch.current++; clearSyncNotes(); }, [view, mode]);
    const wiping = reactExports.useRef(false); // set while leaving sync resets the device: nothing may be written back
    const syncLoading = reactExports.useRef(false); // never push a partial post-join restore
    saveStateRef.current = () => {
        if (!restored || wiping.current || syncLoading.current || (isJoined() && !syncReady()) || preferenceLane.current !== (view === 'instinct' ? 'instinct' : 'owner')) return;
        if (switchingPreferences.current) { switchingPreferences.current = false; return; }
        const w = workRef.current;
        const sc = scrollerRef.current;
        // besides the export payload: which pieces are unfolded and where the page was scrolled to
        const harvested = w ? harvestAll(w) : null;
        // snapshots (past selves) capture what a piece said before each round of edits
        if (w && harvested && harvested.some((x, i) => x !== w[i])) {
            setWork(harvested);
        }
        const current = makePayload(harvested);
        layoutProfiles.current ??= migrateLayouts(null, ownerSettings.current ?? current.settings, bridgeSettings.current ?? bridgeDefaults());
        layoutProfiles.current[preferenceLane.current][deviceRef.current] = layoutOnly(current.settings);
        if (preferenceLane.current === 'instinct') bridgeSettings.current = current.settings;
        else ownerSettings.current = current.settings;
        const payload = {
            ...current,
            settings: ownerSettings.current,
            layoutProfiles: layoutProfiles.current,
            ...(bridgeSettings.current ? { bridgeSettings: bridgeSettings.current } : {}),
            uiPresets,
            ...(adminProfilesBinding.current===token() && adminProfilesRemote.current!==undefined?{adminProfiles:adminProfilesRemote.current}:{}),
            mode,
            open,
            view,
            folders: ownFolders,
            folderNames,
            goneFolders,
            shares: sharesRef.current,
            scroll: sc ? Math.round(sc.scrollTop) : 0,
        };
        // never re-scope this session's content under a different identity (leave/wipe mid-session)
        if (bootStateToken && token() !== bootStateToken) return null;
        const serialized = JSON.stringify(payload), receipt = durability.prepare(payload);
        try {
            // scoped copy: only this profile's sessions may apply it later (card 20261024-001)
            const w = writeScopedWithCustody(isJoined() ? cachedScope(token()) : null, payload);
            if (w.held) {
                showNote('unreadable admin layout data could not be kept aside (device storage) · saving is paused until it can');
                return payload; // no local replace, no push: the previous copy still holds the raw value
            }
            durability.confirm(receipt, { kind: 'local', written: w.stored, readback: w.readback });
        } catch { /* recovery final stays held; online-save status is separate */ }
        schedulePush(payload);
        return payload;
    };
    /* put a saved state on the page: from this browser on load, or from the sync service.
       keepScroll: the save comes from another device, so its scroll position is not ours */
    const applySaved = (saved, keepScroll) => {
        let mode = 'read';
        let data = {};
        try {
            data = JSON.parse(saved);
            mode = data.mode === 'draft' ? 'draft' : 'read';
        } catch {
            /* ignored below */
        }
        if (!keepScroll && Object.hasOwn(data, 'adminProfiles') && data.adminProfiles != null && !cleanAdminProfileState(data.adminProfiles)) {
            // an unreadable admin value in this device's own stored copy is never mistaken for the account's value
            if (holdAdminRaw('local', data.adminProfiles)) showNote('unreadable admin layout data on this device was kept aside');
            data = { ...data }; delete data.adminProfiles;
        }
        setSharesBoth(Array.isArray(data.shares) ? data.shares.filter(isShareEntry) : []);
        setUiPresets(cleanUiPresets(data.uiPresets));
        if(Object.hasOwn(data,'adminProfiles')) {
            const savedAdmin=cleanAdminProfileState(data.adminProfiles);
            adminProfilesRemote.current=data.adminProfiles;
            adminProfilesHeld.current=data.adminProfiles!=null&&!savedAdmin;
            adminProfilesBinding.current=token()||null;
            adminProfiles.current=savedAdmin?.profiles??{};
            if(adminVerifiedBinding.current===token() && token())setAdminType({...adminDefaults(),...(!adminProfilesHeld.current?adminProfiles.current[deviceRef.current]:{}),deviceLane:deviceRef.current});
        }else if(adminProfilesBinding.current===null){adminProfilesBinding.current=token()||null;}

        layoutProfiles.current = migrateLayouts(data.layoutProfiles, data.settings, data.bridgeSettings ?? bridgeDefaults());
        ownerSettings.current = { ...bridgeDefaults(), ...data.settings, ...layoutProfiles.current.owner[deviceRef.current] };
        bridgeSettings.current = { ...bridgeDefaults(), ...data.bridgeSettings, ...layoutProfiles.current.instinct[deviceRef.current] };
        doImport(JSON.stringify({ ...data, settings: ownerSettings.current }), { mode });
        if (preferenceLane.current === 'instinct') applySettings(bridgeSettings.current ?? ownerSettings.current);
        // fold state: only true/false flags are taken back; pieces that no longer exist just never render
        if (data.open && typeof data.open === 'object') {
            const flags = {};
            for (const [id, v] of Object.entries(data.open))
                if (typeof v === 'boolean') flags[id] = v;
            setOpen(flags);
        }
        const own = readFolders(data.folders);
        setOwnFolders(own);
        const names = {};
        if (data.folderNames && typeof data.folderNames === 'object') {
            for (const [id, t] of Object.entries(data.folderNames))
                if (typeof t === 'string' && t.trim()) names[id] = t;
        }
        setFolderNames(names);
        setGoneFolders(
            Array.isArray(data.goneFolders)
                ? data.goneFolders.filter((x) => typeof x === 'string')
                : [],
        );
        const fromHash = viewFromHash(own);
        if (fromHash) setView(fromHash);
        else if (
            typeof data.view === 'string' &&
            (data.view === 'home' || [...FOLDERS, ...own].some((f) => f.id === data.view))
        )
            setView(data.view);
        // scroll position: applied after the restored pieces have laid out (two frames)
        const top = typeof data.scroll === 'number' ? data.scroll : 0;
        if (top > 0 && !keepScroll)
            requestAnimationFrame(() =>
                requestAnimationFrame(() => scrollerRef.current?.scrollTo({ top })),
            );
    };
    /* after leaving sync: clear everything this page keeps in the browser (its own keys only - the
       github.io origin is shared) and reload into a fresh page, as a first visit would see it */
    const resetDevice = ({ preserveLegacy = true } = {}) => {
        wiping.current = true;
        try {
            for (const k of Object.keys(localStorage))
                if ((k.startsWith('middots') || k.startsWith('wt-')) && !(preserveLegacy && ['middots-admin-typography','middots-admin-layout-profiles'].includes(k))) localStorage.removeItem(k);
        } catch {
        }
        void forgetAllFonts().finally(() => {
            location.replace(location.pathname + location.search);
        });
    };
    const wipeDevice = () => {
        // The closing curtain precedes the fresh-visit logo; the page may not write
        // a provisional empty state while it waits to reload.
        wiping.current = true;
        try { sessionStorage.setItem('middots-wipe-welcome', '1'); } catch { }
        setWipeCurtain(true);
        window.setTimeout(() => resetDevice({ preserveLegacy: false }), 1800);
    };
    /* A newer service copy never replaces this page's changes: they are merged first. Unsent edits (a dictated
       paragraph, typing in progress) are read from the page itself, so they survive another device's save. */
    /* sync-quota-recovery r1 (Contracts A/B): unconfirmed IndexedDB recovery records are the source of
       truth for their pieces until a push confirms them - they overlay both the reload restore and the
       merge result, so another device's copy never renders over unconfirmed local text. */
    const overlayRecovery = async (state) => {
        let recs; try { recs = await recoveryRecords(); } catch { return state; }
        if (!state || !Array.isArray(state.pieces) || !recs.length) return state;
        const pieces = [...state.pieces];
        for (const r of recs) {
            const i = pieces.findIndex(p => p && p.id === r.pieceId);
            if (i >= 0) {
                const p = pieces[i], ci = p.current || 0, versions = [...(p.versions || [])];
                if (versions[ci]) versions[ci] = { ...versions[ci], lines: r.lines };
                pieces[i] = { ...p, title: r.title, versions };
            } // else: the piece is gone from the state - the record stays HELD (panel copy/download), never auto-restored
        }
        return { ...state, pieces };
    };
    /* r2 (architect notice inventory A): the rail's status feed, copy/download handlers and mount moved
       INTO the normal sync panel (account.js SyncControl); no floating box exists any more. */
    const applyRemote = async (r, adminRetry = false) => {
        if (!currentRead(r)) return;
        if (r.restoring && r.state === null) {
            adminProfilesBinding.current=token()||null;adminProfilesRemote.current=undefined;adminProfilesHeld.current=false;adminProfiles.current={};
            acceptRemote(r.rev, r.state, r); // confirmed empty server state, not a failed read
            return;
        }
        const capturedAdminEpoch = adminEditEpoch.current;
        const retryAdminRestore = () => {
            if (!currentRead(r)) return;
            if (!adminRetry) return applyRemote(r, true); // one fresh merge only, never an unbounded retry loop
            showNote('admin layout changed during sync · latest edit kept for the next sync');
        };
        const captured = saveStateRef.current(); // keep fresh page edits even when storage is full
        let scopeNow = cachedScope(token()); // refreshed below; the write-back reuses it
        let local = captured ?? null;
        if (!local) {
            // the stored copy is applied only under its own profile's scope: another
            // account's residue (e.g. after a wipe) is never merged into this account
            try {
                scopeNow = await scopeForToken(token());
                const read = readScopedState(storeGet(STATE_KEY), scopeNow);
                local = read.apply ? JSON.parse(read.stateText) : null;
            } catch { local = null; }
        }
        // First restore is additive: a missing local piece is not proof of deletion.
        // Stale or legacy bases cannot erase the current remote shelf.
        const base = r.restoring ? null : (getBase() ?? (syncLoading.current ? local : null));
        if (!currentRead(r)) return;
        if (adminEditEpoch.current !== capturedAdminEpoch) return retryAdminRestore();
        if (adminRetry && local && typeof local === 'object' && !Array.isArray(local) && adminProfilesBinding.current === token() && adminProfilesRemote.current !== undefined && !adminProfilesHeld.current) {
            local = { ...local, adminProfiles: adminProfilesRemote.current }; // current edit even when restore blocks ordinary save
        }
        const merged = mergeStates(base, local, r.state);
        const custScope = isJoined() ? scopeNow : null;
        let keptAside = false;
        if (merged.adminConflicts.some(conflict => conflict.reason?.endsWith('-corrupt-held'))) {
            // key-level hold: pieces, settings and the revision keep merging. Each unreadable raw value keeps its own custody:
            // remote stays unchanged on the account, local and sync-base copies are kept aside in the scoped device copy.
            const rawAdmin = merged.state.adminProfiles;
            adminProfilesHeld.current = rawAdmin != null && !cleanAdminProfileState(rawAdmin);
            if (adminProfilesHeld.current) { adminProfilesRemote.current = rawAdmin; adminProfilesBinding.current = token() || null; }
            for (const conflict of merged.adminConflicts) {
                const h = conflict.held;
                if (!h || typeof h !== 'object') continue;
                if (h.local != null && !cleanAdminProfileState(h.local) && holdAdminRaw('local', h.local, custScope)) keptAside = true;
                if (h.base != null && !cleanAdminProfileState(h.base) && holdAdminRaw('base', h.base, custScope)) keptAside = true;
            }
            if (adminProfilesHeld.current) showNote('admin layout data on the account is unreadable · left unchanged there, edits paused' + (keptAside ? ' · unreadable copies on this device are kept aside' : ''));
            else if (keptAside) showNote('unreadable admin layout data on this device was kept aside · the account copy is used');
        }
        return overlayRecovery(merged.state).then(overlaid => { // Contract A: unconfirmed records stay rendered
        if (!currentRead(r)) return;
        if (adminEditEpoch.current !== capturedAdminEpoch) return retryAdminRestore();
        const text = JSON.stringify(overlaid);
        const same = local && JSON.stringify(local) === text;
        let persisted = true;
        try { persisted = writeScopedWithCustody(custScope, overlaid).durable; } catch { persisted = false; }
        if (persisted) adminCustodyDirty.current = false;
        else if (adminCustodyDirty.current) {
            // unreadable admin data was set aside in memory only: never advance the revision or replace the sync base
            // (which would delete the only other copy) until the scoped device copy really holds it
            showNote('could not keep unreadable admin layout data aside (device storage) · this sync is paused until it can');
            return;
        }
        if (!same) {
            // this device's scroll wins, restored once the new pieces have laid out
            const sc = scrollerRef.current;
            const keep = sc ? sc.scrollTop : 0;
            applySaved(text, true);
            if (sc)
                requestAnimationFrame(() =>
                    requestAnimationFrame(() => sc.scrollTo({ top: keep })),
                );
        }
        acceptRemote(r.rev, r.state, r);
        if (merged.conflicts.length) {
            const ids = merged.conflicts.map((c) => c.piece);
            const saved = saveRecovery({ kind: 'merge', conflicts: merged.conflicts, local: piecesOf(local, ids), remote: piecesOf(r.state, ids) });
            showNote('a piece conflict was found' + (saved ? ' · a recovery copy of the differing pieces is on this device' : ' · recovery copy unavailable'));
        }
        if (!r.restoring && merged.localChanged && local) {
            const editEpoch = localEditEpoch.current;
            void pushMerged(overlaid, r.rev).then(res => // the pushed merge carries the overlaid records
                handleMergeReceipt(res, overlaid, { current: result => currentWrite(result) && localEditEpoch.current === editEpoch, retry: retryMerged }));
        }
        });
    };
    // once, on load: bring back the saved state before anything is written over it,
    // then ask the sync service for anything newer from another device
    reactExports.useEffect(() => {
        const saved = storeGet(STATE_KEY);
        if (saved) void (async () => { // Contract B: unconfirmed records re-apply on reload
            // card 20261024-001: a wiped profile's leftover copy is never shown to another
            // session; it stays stored, unseen (the recovery store's r2 privacy precedent)
            const read = readScopedState(saved, await scopeForToken(token()));
            if (!read.apply) return;
            try { applySaved(JSON.stringify(await overlayRecovery(JSON.parse(read.stateText)))); }
            catch { applySaved(read.stateText); }
        })();
        void scopeForToken(token()); // warm the cache for saveState's synchronous scope read
        onNewer(applyRemote);
        onSignedOut(resetDevice); // the code was changed on another device: this one goes fresh
        if (isJoined()) {
            syncLoading.current = true;
            const restoringToken = token();
            void Promise.all([pull(), loadPrivate()]).then(([r, loaded]) => {
                if (token() !== restoringToken) return;
                if (loaded) acceptArchive(restoringToken);
                if (r) applyRemote(r);
                if (loaded) setShelfRev((n) => n + 1);
                syncLoading.current = false;
                setRestored(true); // no provisional empty shelf is pushed before restore
            }).catch(() => { syncLoading.current = false; setRestored(true); });
        } else setRestored(true);
    }, []);
    // Wait for the authenticated restore so existing remote leaves beat legacy device flags.
    reactExports.useEffect(() => {
        if (restored) setUiPresets(previous => {
            const next = migrateAdminFolds(previous);
            return JSON.stringify(next) === JSON.stringify(previous) ? previous : next;
        });
    }, [restored]);
    // any change to settings, pieces or mode is saved on the next render
    reactExports.useEffect(() => {
        saveStateRef.current();
    }, [
        restored,
        adminType,
        uiPresets,
        textPt,
        indexPt,
        textWidthEm,
        lh,
        bg,
        palettePages,
        hz,
        inverted,
        eraId,
        soundOn,
        platen,
        focusDim,
        commit,
        bodyFace,
        titleFace,
        layoutId,
        axisValues,
        pieceLayouts,
        work,
        mode,
        open,
        view,
        ownFolders,
        folderNames,
        goneFolders,
        shares,
    ]);
    // edits in progress: save after a pause in typing, and when the page goes away
    reactExports.useEffect(() => {
        let timer;
        const onInput = () => {
            localEditEpoch.current++;
            window.clearTimeout(timer);
            timer = window.setTimeout(() => saveStateRef.current(), 700);
        };
        const flush = () => saveStateRef.current();
        const refreshJoined = async () => {
            const restoringToken = token();
            const [r, loaded] = await Promise.all([pull(), syncReady() ? Promise.resolve(false) : loadPrivate()]);
            if (token() !== restoringToken) return;
            if (loaded) { acceptArchive(restoringToken); setShelfRev(n => n + 1); }
            if (r) applyRemote(r);
        };
        // hidden: save and send now; visible again: pick up what another device saved meanwhile
        const onVisibility = () => {
            if (document.visibilityState === 'hidden') {
                flush();
                void pushNow(true);
            } else
                void refreshJoined();
        };
        document.addEventListener('input', onInput, true);
        const sc = scrollerRef.current;
        let scrollTimer;
        const onScroll = () => {
            window.clearTimeout(scrollTimer);
            scrollTimer = window.setTimeout(() => saveStateRef.current(), 400);
        };
        sc?.addEventListener('scroll', onScroll, { passive: true });
        let lastFocusPull = 0;
        const onFocusReturn = () => {
            const now = Date.now();
            if (syncLoading.current || now - lastFocusPull < 30000) return;
            lastFocusPull = now;
            void refreshJoined();
        };
        document.addEventListener('visibilitychange', onVisibility);
        window.addEventListener('focus', onFocusReturn);
        window.addEventListener('pagehide', flush);
        return () => {
            window.clearTimeout(timer);
            window.clearTimeout(scrollTimer);
            sc?.removeEventListener('scroll', onScroll);
            document.removeEventListener('input', onInput, true);
            document.removeEventListener('visibilitychange', onVisibility);
            window.removeEventListener('focus', onFocusReturn);
            window.removeEventListener('pagehide', flush);
        };
    }, []);
    /* the frame's sandbox forbids downloads outright, and a blob: made here belongs to our opaque origin, so the
       helper tab builds its OWN blob from the text we hand it and links to that. the whole export is also printed
       on that page so select-all + copy works even where a browser refuses the save */
    const downloadExport = () => {
        if (!overlay) return;
        const name = `dreamwake-drafts-${nowStamp().replace(/[.: ]/g, '-')}.json`;
        {
            // a normal page may download directly: a blob link with a file name, clicked once
            const url = URL.createObjectURL(new Blob([overlay.text], { type: 'application/json' }));
            const a = document.createElement('a');
            a.href = url;
            a.download = name;
            document.body.appendChild(a);
            a.click();
            a.remove();
            window.setTimeout(() => URL.revokeObjectURL(url), 60000);
            return;
        }
    };
    const exportAreaRef = reactExports.useRef(null);
    const copyExport = () => {
        if (!overlay) return;
        let ok = false;
        const ta = exportAreaRef.current;
        if (ta) {
            ta.focus();
            ta.select();
            try {
                ok = document.execCommand('copy');
            } catch {
                ok = false;
            }
        }
        const done = () => setOverlay((o) => (o ? { ...o, copied: true, error: undefined } : o));
        if (ok) {
            done();
            return;
        }
        try {
            void navigator.clipboard.writeText(overlay.text).then(done, () =>
                setOverlay((o) =>
                    o
                        ? {
                              ...o,
                              error: 'copy was blocked - the text is selected, press cmd+c',
                          }
                        : o,
                ),
            );
        } catch {
            setOverlay((o) =>
                o
                    ? {
                          ...o,
                          error: 'copy was blocked - the text is selected, press cmd+c',
                      }
                    : o,
            );
        }
    };
    /* the new-piece plus over the index is the add plus itself now, pinned on the horizon
       at the left edge (his ruling, 27 Sep 19:29) - this div only keeps the two-line gap
       above the first piece's title. Reading mode crosses into draft with the new page in hand */
    const listPlus = jsxRuntimeExports.jsx('div', {
        className: 'list-plus',
        children: jsxRuntimeExports.jsx(AddPlus, {
            label: 'new piece',
            onClick: () => {
                if (mode !== 'draft') {
                    modePrefRef.current = 'draft';
                    enterDraft(view);
                }
                addDraft(view);
            },
        }),
    });
    return jsxRuntimeExports.jsx(UiPresetsContext.Provider, { value: { uiPresets, setUiPresets }, children: jsxRuntimeExports.jsxs('div', {
        className: `scroller${adminSide ? ' admin-surface' : ''}`,
        style: adminStyle,
        ref: scrollerRef,
        onPointerDown: (e) => {
            if (mode !== 'draft') return;
            if (e.pointerType === 'mouse' && e.button !== 0) return;
            // the scrollbar belongs to the scroller element: a press on it is not a press on empty space
            const sc = scrollerRef.current;
            if (sc && e.target === sc && e.clientX >= sc.getBoundingClientRect().left + sc.clientWidth) return;
            if (
                e.target.closest(
                    // layout wrappers (.story, .story-body) are empty space; the head, the text and the history/version widgets are not
                    '.story-text, .story-head, .story-audio, .version-stack, .hist-pin, .history-actions, .snap-peek, button, a, input, textarea, select, [contenteditable], .controls, .io-panel, .plumb, .archive-end, .seam',
                )
            )
                return;
            pagePress(e);
        },
        onPointerUp: pageRelease,
        onPointerLeave: pageRelease,
        onPointerCancel: pageRelease,
        onPointerMove: pageMove,
        children: [
            jsxRuntimeExports.jsx('div', {
                className: 'seam standalone',
                'aria-hidden': 'true',
            }),
            jsxRuntimeExports.jsxs('main', {
                className: `page${onCover || (view === 'instinct' && !instinctNavigation?.folder) ? ' home-surface' : ' folder-surface'}`,
                children: [
                    view === 'instinct' ? (adminVerified ? jsxRuntimeExports.jsx(InstinctShelf, { measure: textWidthEm, onMeasure: setTextWidthEm, onNavigation: setInstinctNavigation, folds: uiPresets.instinctViewer.folds, onFoldChange: changeInstinctFold }) : null)
                        : view === 'admin' && mode === 'read'
                        ? jsxRuntimeExports.jsx(AdminPage, { faces: [bodyFace, titleFace], go: setView, session: adminSession, onDenied: () => setShelfRev((n) => n + 1) })
                        : (view === 'admin/logo' || view === 'admin/tango') && mode === 'read'
                        ? jsxRuntimeExports.jsx(LogoLibraryPage, { go: setView })
                        : view === 'admin/audio' && mode === 'read'
                        ? jsxRuntimeExports.jsx(AudioMigrationPage, { go: setView })
                        : view === 'admin/edit' && mode === 'read'
                        ? jsxRuntimeExports.jsx(EditorPage, { go: setView })
                        : view === 'admin/mailing' && mode === 'read'
                        ? jsxRuntimeExports.jsx(MailingPage, { go: setView })
                        : view === 'admin/changes' && mode === 'read'
                        ? jsxRuntimeExports.jsx(ChangesPage, { go: setView })
                        : view === 'admin/history' && mode === 'read'
                        ? jsxRuntimeExports.jsx(HistoryPage, { go: setView })
                        : mode === 'read' && view === 'home'
                        ? jsxRuntimeExports.jsx(Cover, {
                              welcome,
                              onWelcomeCycle: finishWelcome,
                              folders: liveFolders().map(named),
                              count: folderCount,
                              onOpen: openFolder,
                              onCreate: createFolder,
                              onRename: renameFolder,
                              onDelete: deleteFolder,
                          })
                        : mode === 'read'
                          ? jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, {
                                children: [
                                    jsxRuntimeExports.jsx('div', {
                                        className: 'logo-slot',
                                        children: jsxRuntimeExports.jsx(Logo, {}),
                                    }),
                                    listPlus,
                                    readingList(view).map((p, i, arr) =>
                                        jsxRuntimeExports.jsx(
                                            Story,
                                            {
                                                piece: p,
                                                num: arr.length - i,
                                                open: !!open[p.id],
                                                onToggle: () => toggleFold(p.id),
                                                shared: !!findActiveShare(shares, 'piece', p.id),
                                                onSharePress: shareClipStart,
                                                onShareToggle: (clip) => void togglePieceShare(p, clip),
                                                onShareHover: () => void recopyShare(p.id),
                                                shareNotice: shareNotice?.key === p.id ? shareNotice : null,
                                                onShareNoticeDone: () => setShareNotice(null),
                                                onShareNoticeCopied: () => setShareNotice((n) => (n ? { ...n, kind: 'copied' } : n)),
                                                onRestore: (snap) => {
                                                    restoreSnap(p.id, snap);
                                                    modePrefRef.current = 'draft';
                                                    enterDraft(folderOf(p));
                                                },
                                                onDraft: () => {
                                                    modePrefRef.current = 'draft';
                                                    enterDraft(folderOf(p));
                                                },
                                                onRemoveSnap: work ? removeSnap : null,
                                                onRemoveVersion: work ? removeVersion : null,
                                                onRemove: work
                                                    ? (p.published && !token$1() ? null : removeDraft)
                                                    : token$1()
                                                      ? removePublished
                                                      : null,
                                                measure: pieceLayouts[p.id]?.[device]?.textWidthEm ?? textWidthEm,
                                                onMeasure: setTextWidthEm,
                                                layoutStyle: pieceLayoutStyle(p.id),
                                                layout: pieceLayouts[p.id]?.[device]?.layout,
                                            },
                                            p.id,
                                        ),
                                    ),
                                    
                                ],
                            })
                          : jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, {
                        children: [
                          jsxRuntimeExports.jsx('div', {
                              className: 'logo-slot',
                              children: jsxRuntimeExports.jsx(Logo, {}),
                          }),
                          listPlus,
                          (work ?? [])
                                .filter((wp) => wp.folder === view)
                                .map((wp, i, arr) =>
                                    jsxRuntimeExports.jsx(
                                        WorkStory,
                                        {
                                            wp: wp,
                                            num: arr.length - i,
                                            resting: activeId !== wp.id,
                                            onActive: markLayoutContext,
                                            open: !!open[wp.id],
                                            onToggle: () => toggleDraftFold(wp.id),
                                            shared: !!findActiveShare(shares, 'piece', wp.id),
                                            onSharePress: shareClipStart,
                                            onShareToggle: (clip) => void togglePieceShare(draftSharePiece(wp), clip),
                                            onShareHover: () => void recopyShare(wp.id),
                                            shareNotice: shareNotice?.key === wp.id ? shareNotice : null,
                                            onShareNoticeDone: () => setShareNotice(null),
                                            onShareNoticeCopied: () => setShareNotice((n) => (n ? { ...n, kind: 'copied' } : n)),
                                            register: register,
                                            onEditInput: (id) => { markLayoutContext(id); stampEdit(id); },
                                            onLoadVersion: loadVersion,
                                            onDuplicate: duplicateVersion,
                                            onRemoveVersion: removeVersion,
                                            onRemoveSnap: removeSnap,
                                            onRemove: removeDraft,
                                            onRestore: restoreSnap,
                                            onToggleEndmark: toggleEndmark,
                                            measure: layoutContextId === wp.id ? rail.textWidthEm : textWidthEm,
                                            onMeasure: layoutContextId === wp.id ? bindLayoutField('textWidthEm', setTextWidthEm) : setTextWidthEm,
                                            layoutStyle: pieceLayoutStyle(wp.id, true),
                                            layout: presetContextId === wp.id ? pieceLayouts[wp.id]?.[device]?.layout : undefined,
                                        },
                                        wp.id,
                                    ),
                                ),
                          
                        ],
                    }),
                    jsxRuntimeExports.jsx('div', { id: 'sync-status-anchor', style: { minWidth: 0, maxWidth: '100%', overflowAnchor: 'none' } }, 'sync-status-anchor'),
                ],
            }),
            mode === 'draft' && jsxRuntimeExports.jsx(FxPalette, {}),
            !onCover &&
                jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, {
                    children: [
                        !adminSide && view !== 'instinct' && jsxRuntimeExports.jsx(IndexTick, { value: indexW, onSet: setIndexW }),
                        !adminSide && jsxRuntimeExports.jsx('span', {
                            style: { display: 'contents' },
                            onPointerDownCapture: (e) => {
                                if (!e.target.closest?.('.idx-toggle')) return;
                                dotHeld.current = false;
                                dotXY.current = [e.clientX, e.clientY];
                                window.clearTimeout(dotHold.current);
                                dotHold.current = window.setTimeout(() => { dotHeld.current = true; foldAllRef.current(); }, 550);
                            },
                            onPointerMoveCapture: (e) => {
                                // a finger or mouse that wanders off the dot (more than 10px) is no hold
                                if (dotXY.current && Math.hypot(e.clientX - dotXY.current[0], e.clientY - dotXY.current[1]) > 10) window.clearTimeout(dotHold.current);
                            },
                            onPointerUpCapture: () => window.clearTimeout(dotHold.current),
                            onPointerCancelCapture: () => window.clearTimeout(dotHold.current),
                            onPointerLeave: () => window.clearTimeout(dotHold.current),
                            onContextMenuCapture: (e) => { if (e.target.closest?.('.idx-toggle')) e.preventDefault(); },
                            onClickCapture: (e) => { if (dotHeld.current) { dotHeld.current = false; e.stopPropagation(); e.preventDefault(); } },
                            children: jsxRuntimeExports.jsx(IndexHide, { contextId: uiLane(view), hidden: uiPresets[uiLane(view)].indexHidden, onHiddenChange: value => updateUiPreset(uiLane(view), 'indexHidden', value) }),
                        }),
                        jsxRuntimeExports.jsx(MeasureTick, {
                            value: adminSide ? adminType.textWidthEm : textWidthEm,
                            onSet: adminSide ? (v) => updateAdminType('textWidthEm', v) : setTextWidthEm,
                        }),
                    ],
                }),
            renderApp({ device, onShareFolder: shareFolder, adminType: adminSide ? {
                ...adminType, readerFaces: [bodyFace, titleFace], setTaste: setAdminTaste, faceOpen: adminFaceOpen, setFaceOpen: setAdminFaceOpen,
                update: updateAdminType,
            } : null, addDraft, adminVerified, instinctNavigation, axisKeep: bindAxis, axisLive: bindAxis, axisValues: rail.axisValues, pieceLayout: { hasOverride: !!(presetContextId && presetPieceLayout), onReset: resetPieceLayout }, palette, setPalette, bg, bodyFace: rail.bodyFace, layoutId: presetPieceLayout?.layout ?? layoutId, stepLayout: stepLayoutBound, previewLayout, colorRef, commit, ctlOpen, doExport, dropFace, enterDraft, eraId, exportAs, faceOpen, focusDim, goToHit, hz: contextPieceLayout ? rail.hz : hzEff, indexPt: rail.indexPt, leaveDraft, lh: rail.lh, liveFolders, logoRoaming, mode, modePrefRef, named, onCover, openFolder, openView, platen, resetDevice, wipeDevice, searchItems, setBg, setBodyFace: bindLayoutField('textFace', setBodyFace), setCommit, setCtlOpen, setEraId, setFaceOpen, setFocusDim, setHz: bindLayoutField('horizon', setHz), setIndexPt: bindLayoutField('indexSizePt', setIndexPt), setInverted, setLh: bindLayoutField('lineHeight', setLh), setLogoRoaming, setOverlay, setPlaten, setSoundOn, setTaste, setTextPt: bindLayoutField('fontSizePt', setTextPt), setTextWidthEm: bindLayoutField('textWidthEm', setTextWidthEm), setTitleFace: bindLayoutField('titleFace', setTitleFace), setView, soundOn, syncJoined, syncRekeyed, shareNotice, onShareNoticeDone: () => setShareNotice(null), onShareNoticeCopied: () => setShareNotice((n) => (n ? { ...n, kind: 'copied' } : n)), textPt: rail.textPt, textWidthEm: rail.textWidthEm, titleFace: rail.titleFace, uploadFace, uploads, view }),
            wipeCurtain && jsxRuntimeExports.jsxs('div', {
                className: 'wipe-curtain', role: 'status', 'aria-label': 'gone gone baby',
                children: ['gone', 'gone', 'baby'].map((word, i) =>
                    jsxRuntimeExports.jsx('div', { className: 'wipe-curtain-line', children: [...word].map((ch, j) =>
                        jsxRuntimeExports.jsx('span', { children: ch }, j)) }, i)),
            }),
            jsxRuntimeExports.jsx('input', {
                type: 'file',
                accept: 'application/json,.json,text/plain,.txt',
                ref: fileRef,
                style: { display: 'none' },
                onChange: (e) => {
                    const f = e.target.files?.[0];
                    if (!f) return;
                    const reader = new FileReader();
                    reader.onload = () => doImport(String(reader.result ?? ''));
                    reader.readAsText(f);
                    e.target.value = '';
                },
            }),
            overlay &&
                jsxRuntimeExports.jsx('div', {
                    className: 'io-overlay',
                    onClick: () => setOverlay(null),
                    children: jsxRuntimeExports.jsxs('div', {
                        className: 'io-panel',
                        onClick: (e) => e.stopPropagation(),
                        children: [
                            jsxRuntimeExports.jsx('p', {
                                className: 'io-title',
                                children:
                                    overlay.kind === 'export' ? 'draft export' : 'draft import',
                            }),
                            jsxRuntimeExports.jsx('p', {
                                className: 'io-note',
                                children:
                                    overlay.kind === 'export'
                                        ? 'copy puts the whole export on your clipboard. save opens a small tab, click the file name there'
                                        : 'paste a dreamwake export below, or choose the file',
                            }),
                            jsxRuntimeExports.jsx('textarea', {
                                ref: exportAreaRef,
                                value: overlay.text,
                                readOnly: overlay.kind === 'export',
                                onChange: (e) =>
                                    setOverlay((o) =>
                                        o ? { ...o, text: e.target.value, error: undefined } : o,
                                    ),
                                onFocus: (e) => {
                                    if (overlay.kind === 'export') e.target.select();
                                },
                                spellCheck: false,
                            }),
                            overlay.error &&
                                jsxRuntimeExports.jsx('p', {
                                    className: 'io-error',
                                    children: overlay.error,
                                }),
                            jsxRuntimeExports.jsxs('div', {
                                className: 'io-row',
                                children: [
                                    overlay.kind === 'export'
                                        ? jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, {
                                              children: [
                                                  jsxRuntimeExports.jsx('button', {
                                                      type: 'button',
                                                      onClick: copyExport,
                                                      children: overlay.copied ? 'copied' : 'copy',
                                                  }),
                                                  jsxRuntimeExports.jsx('button', {
                                                      type: 'button',
                                                      onClick: downloadExport,
                                                      children: 'save file',
                                                  }),
                                              ],
                                          })
                                        : jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, {
                                              children: [
                                                  jsxRuntimeExports.jsx('button', {
                                                      type: 'button',
                                                      onClick: () => fileRef.current?.click(),
                                                      children: 'choose file',
                                                  }),
                                                  jsxRuntimeExports.jsx('button', {
                                                      type: 'button',
                                                      onClick: () => doImport(overlay.text),
                                                      children: 'apply',
                                                  }),
                                              ],
                                          }),
                                    jsxRuntimeExports.jsx('button', {
                                        type: 'button',
                                        onClick: () => setOverlay(null),
                                        children: 'close',
                                    }),
                                ],
                            }),
                        ],
                    }),
                }),
        ],
    }) });
}

/* ==========================================================================
 * ShareViewApp - the read-only recipient side of a share link
 * --------------------------------------------------------------------------
 * Whoever holds the link gets the normal reading screen driven by the sealed
 * snapshot: the same shell (logo, index, rails), the same Story renderer, the
 * same layout calculations - never the owner App, its local state, or a
 * mutation surface (readOnly gates every one). Appearance controls work but
 * live in this component's memory only: nothing is saved, a reload restores
 * the snapshot. Links minted before snapshots existed open with the normal
 * reading defaults.
 * ========================================================================== */
export const SHARE_DEFAULTS = {
    fontSizePt: 19, indexSizePt: 10, textWidthEm: 29, lineHeight: 1.42, horizon: 0,
    textFace: 'eb-garamond', titleFace: 'fragment-mono', faceAxes: {}, layout: LAYOUT_DEFAULT,
};
/* the recipient's single shelf: everything the link sealed, nothing it did not */
const SHARE_FOLDER = { id: 'shared', title: 'this link' };

export function ShareViewApp({ syncUrl, match, preload }) {
    const [state, setState] = reactExports.useState(() =>
        preload ? { phase: 'ready', model: preload } : { phase: 'loading', model: null });
    reactExports.useEffect(() => {
        if (preload) return undefined;
        let live = true;
        setState({ phase: 'loading', model: null });
        loadShare(syncUrl, match)
            .then((m) => { if (live) setState({ phase: 'ready', model: m }); })
            .catch((e) => { if (live) setState({ phase: 'gone', model: null, revokedAt: e?.code === 'revoked' ? e.revokedAt ?? null : undefined }); });
        return () => { live = false; };
    }, [syncUrl, match, preload]);
    /* key on the phase: every phase gets a FRESH mount. Without it the loading mount (model null)
       kept its state when the model arrived - every useState initialiser had already latched the
       defaults, and the link opened with the default profile instead of the sharer's snapshot
       (owner report 2026-10-21). */
    if (state.phase === 'loading') return jsxRuntimeExports.jsx(ShareViewReady, { key: 'loading', model: null, status: '\u00B7', loading: true });
    if (state.phase === 'ready' && !state.model.pieces.length)
        return jsxRuntimeExports.jsx(ShareViewReady, { key: 'ready', model: state.model, status: 'nothing is shared here yet' });
    if (state.phase === 'gone')
        return jsxRuntimeExports.jsx(ShareViewReady, {
            key: 'gone',
            model: null,
            status: 'Nothing opens at this link',
            statusWhy: 'The link was revoked, or it was copied without its key',
            statusDate: state.revokedAt ?? null,
        });
    return jsxRuntimeExports.jsx(ShareViewReady, { key: 'ready', model: state.model });
}

export function ShareViewReady({ model, status = null, statusWhy = null, statusDate = null, loading = false }) {
    const g = model?.presentation?.global;
    const pieces = model?.pieces ?? [];
    /* home means the plain middots page, never this link again: the share hash stays behind
       (owner order 2026-10-21: the home button did nothing, the logo walked back into the link) */
    const goHome = () => location.assign('/');
    const [device, setDevice] = reactExports.useState(layoutDevice);
    reactExports.useEffect(() => {
        const media = matchMedia(MOBILE_QUERY);
        const change = () => setDevice(layoutDevice());
        media.addEventListener('change', change);
        return () => media.removeEventListener('change', change);
    }, []);
    const [inverted, setInverted] = reactExports.useState(g?.inverted ?? false);
    const [textPt, setTextPt] = reactExports.useState(g?.fontSizePt ?? SHARE_DEFAULTS.fontSizePt);
    const [indexPt, setIndexPt] = reactExports.useState(g?.indexSizePt ?? SHARE_DEFAULTS.indexSizePt);
    const [textWidthEm, setTextWidthEm] = reactExports.useState(g?.textWidthEm ?? SHARE_DEFAULTS.textWidthEm);
    const [indexW, setIndexW] = reactExports.useState(300); // INDEX_W_BORN - recipient never reads the owner's stored width
    const [lh, setLh] = reactExports.useState(g?.lineHeight ?? SHARE_DEFAULTS.lineHeight);
    const [hz, setHz] = reactExports.useState(g?.horizon ?? SHARE_DEFAULTS.horizon);
    const [bodyFace, setBodyFace] = reactExports.useState(g?.textFace ?? SHARE_DEFAULTS.textFace);
    const [titleFace, setTitleFace] = reactExports.useState(g?.titleFace ?? SHARE_DEFAULTS.titleFace);
    const [axisValues, setAxisValues] = reactExports.useState(g?.faceAxes ?? {});
    const [layoutId, setLayoutId] = reactExports.useState(g?.layout ?? SHARE_DEFAULTS.layout);
    const [palette, setPaletteState] = reactExports.useState(() => cleanPalette(g?.palette ?? {}));
    const setPalette = (value) => setPaletteState(cleanPalette(value));
    const [bg, setBg] = reactExports.useState(g?.background ?? '');
    const [focusDim, setFocusDim] = reactExports.useState(g?.focusDim ?? true);
    const [logoRoaming, setLogoRoaming] = reactExports.useState(g?.logoRoaming ?? LOGO_ROAMING);
    const [pieceLanes, setPieceLanes] = reactExports.useState(() => {
        const out = {};
        for (const p of pieces) if (p.presentation?.piece) out[p.id] = p.presentation.piece;
        return out;
    });
    const snapshotLanes = reactExports.useRef(pieceLanes); // layout reset = reset to snapshot
    /* the shared text starts UNFOLDED - whoever opens the link is meant to read it
       (owner ruling, final): every piece open; the fold dots still work after that */
    const [open, setOpen] = reactExports.useState(() => Object.fromEntries(pieces.map((p) => [p.id, true])));
    const [indexHidden, setIndexHidden] = reactExports.useState(false);
    const [ctlOpen, setCtlOpen] = reactExports.useState(null);
    const [faceOpen, setFaceOpen] = reactExports.useState(null);
    const [taste, setTaste] = reactExports.useState(null);
    const colorRef = reactExports.useRef(null);
    const scrollerRef = reactExports.useRef(null);
    const dotHold = reactExports.useRef(undefined);
    const dotHeld = reactExports.useRef(false);
    const dotXY = reactExports.useRef(null);

    const globalValues = { fontSizePt: textPt, indexSizePt: indexPt, textWidthEm, lineHeight: lh, horizon: hz, textFace: bodyFace, titleFace, faceAxes: axisValues, layout: layoutId };

    reactExports.useEffect(() => {
        document.documentElement.classList.toggle('inverted', inverted);
    }, [inverted]);
    reactExports.useEffect(() => {
        applyGlobalLayoutVars({ fontSizePt: textPt, indexSizePt: indexPt, textWidthEm, lineHeight: lh });
    }, [textPt, indexPt, textWidthEm, lh]);
    reactExports.useEffect(() => {
        const e = hz > hzMax() ? clampHz(hz) : hz;
        document.documentElement.style.setProperty('--hz', `${e}px`);
    }, [hz]);
    reactExports.useEffect(() => {
        applyPalette(palette, inverted, bg);
    }, [bg, palette, inverted]);
    reactExports.useEffect(() => {
        applyFacesTo(taste?.slot === 'body' ? taste.slug : bodyFace, taste?.slot === 'title' ? taste.slug : titleFace, axisValues);
    }, [bodyFace, titleFace, taste, axisValues]);
    reactExports.useEffect(() => {
        const root = document.documentElement;
        if (layoutId === LAYOUT_DEFAULT) root.removeAttribute('data-layout'); else root.setAttribute('data-layout', layoutId);
    }, [layoutId]);
    reactExports.useEffect(() => {
        document.documentElement.style.setProperty('--index-w', `max(200px, min(${indexW}px, 100vw - 444px))`);
    }, [indexW]);
    useChromeAwake(scrollerRef, []);

    const stepLayout = (dir) => setLayoutId((cur) => { const i = LAYOUTS.findIndex((l) => l.id === cur); return LAYOUTS[(i + dir + LAYOUTS.length) % LAYOUTS.length].id; });
    const previewLayout = (pid) => {
        const root = document.documentElement;
        const use = pid ?? layoutId;
        if (use === LAYOUT_DEFAULT) root.removeAttribute('data-layout'); else root.setAttribute('data-layout', use);
    };
    const bindAxis = (slug, values) => {
        setAxisValues((prev) => ({ ...prev, [slug]: values }));
        const f = faceBySlug(slug);
        if (!f) return;
        if ((taste?.slot === 'body' ? taste.slug : bodyFace) === slug)
            document.documentElement.style.setProperty('--fvs-body', variationSettings(f.axes, values));
        if ((taste?.slot === 'title' ? taste.slug : titleFace) === slug)
            document.documentElement.style.setProperty('--fvs-mono', variationSettings(f.axes, values));
    };
    const scrollTop = () => scrollerRef.current?.scrollTo({ top: 0, behavior: 'smooth' });
    const goToHit = (h) => {
        setOpen((o) => ({ ...o, [h.id]: true }));
        window.setTimeout(() => document.getElementById(h.id)?.scrollIntoView({ block: 'start' }), 80);
    };
    const searchItems = () =>
        pieces.map((p, i, arr) => ({
            id: p.id,
            folder: SHARE_FOLDER.id,
            title: p.title,
            lines: p.blocks.flatMap((b) => (Array.isArray(b) ? b : [b])),
            num: arr.length - i,
        }));

    return jsxRuntimeExports.jsxs('div', {
        ref: scrollerRef,
        className: 'share-view',
        children: [
            jsxRuntimeExports.jsx('div', { className: 'seam standalone', 'aria-hidden': 'true' }),
            jsxRuntimeExports.jsxs('main', {
                className: 'page folder-surface',
                children: [
                    jsxRuntimeExports.jsx('div', {
                        className: 'logo-slot',
                        /* the living mark stays pointer-events:none; its own precise-click catch
                           (catchLogo in reading.js) calls onCatch - here: home, never a reload
                           back into this link */
                        children: jsxRuntimeExports.jsx(Logo, { onCatch: goHome }),
                    }),
                    status !== null &&
                        jsxRuntimeExports.jsxs('section', {
                            className: 'story open',
                            children: [
                                jsxRuntimeExports.jsxs('div', {
                                    className: 'story-head',
                                    children: [
                                        jsxRuntimeExports.jsxs('span', {
                                            className: 'gutter',
                                            children: [
                                                '\u00A0',
                                                jsxRuntimeExports.jsx('span', { className: `fold-dot${loading ? '' : ' shared'}`, 'aria-hidden': 'true', children: '\u00B7' }),
                                            ],
                                        }),
                                        jsxRuntimeExports.jsxs('span', {
                                            className: 'story-head-main',
                                            children: [
                                                jsxRuntimeExports.jsx('span', { className: 'story-title', children: status }),
                                                /* the revocation date sits where a piece's own date sits: under the
                                                   index-side title, gutter padding included - exactly the under-piece
                                                   geometry (the piece's serial is blank here, the alignment is not) */
                                                statusDate &&
                                                    jsxRuntimeExports.jsxs('span', {
                                                        className: 'story-when',
                                                        children: [
                                                            jsxRuntimeExports.jsx('span', { className: 'gutter num', 'aria-hidden': 'true', children: '\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0' }, 'gutter'),
                                                            `revoked ${statusDate.slice(0, 10)}`,
                                                        ],
                                                    }),
                                            ],
                                        }),
                                    ],
                                }),
                                jsxRuntimeExports.jsxs('div', {
                                    className: 'story-fold',
                                    children: [
                                        statusWhy &&
                                            jsxRuntimeExports.jsx('div', {
                                                className: 'story-body',
                                                children: jsxRuntimeExports.jsx('div', {
                                                    className: 'story-text',
                                                    children: jsxRuntimeExports.jsx('p', { children: statusWhy }),
                                                }),
                                            }),
                                        /* the closing middots, exactly as under every piece (owner order
                                           2026-10-21: not improvised - the under-piece design itself) */
                                        jsxRuntimeExports.jsx('p', { className: 'endmark', children: '\u00B7 \u00B7' }),
                                    ],
                                }),
                            ],
                        }),
                    pieces.map((p, i, arr) =>
                        jsxRuntimeExports.jsx(
                            Story,
                            {
                                piece: p,
                                num: arr.length - i,
                                open: !!open[p.id],
                                onToggle: () => setOpen((o) => ({ ...o, [p.id]: !o[p.id] })),
                                onRemove: null,
                                onRemoveSnap: null,
                                onRemoveVersion: null,
                                onRestore: null,
                                onDraft: null,
                                readOnly: true,
                                measure: pieceLanes[p.id]?.[device]?.textWidthEm ?? textWidthEm,
                                onMeasure: setTextWidthEm,
                                layoutStyle: pieceLanes[p.id]?.[device]
                                    ? pieceLayoutStyleOf(effectivePieceLayout(pieceLanes, null, p.id, device, globalValues))
                                    : undefined,
                                layout: pieceLanes[p.id]?.[device]?.layout,
                            },
                            p.id,
                        ),
                    ),
                ],
            }),
            jsxRuntimeExports.jsx(IndexTick, { value: indexW, onSet: setIndexW }),
            jsxRuntimeExports.jsx('span', {
                style: { display: 'contents' },
                onPointerDownCapture: (e) => {
                    if (!e.target.closest?.('.idx-toggle')) return;
                    dotHeld.current = false;
                    dotXY.current = [e.clientX, e.clientY];
                    window.clearTimeout(dotHold.current);
                    dotHold.current = window.setTimeout(() => { dotHeld.current = true; setOpen({}); }, 550);
                },
                onPointerMoveCapture: (e) => {
                    if (dotXY.current && Math.hypot(e.clientX - dotXY.current[0], e.clientY - dotXY.current[1]) > 10) window.clearTimeout(dotHold.current);
                },
                onPointerUpCapture: () => window.clearTimeout(dotHold.current),
                onPointerCancelCapture: () => window.clearTimeout(dotHold.current),
                onPointerLeave: () => window.clearTimeout(dotHold.current),
                onContextMenuCapture: (e) => { if (e.target.closest?.('.idx-toggle')) e.preventDefault(); },
                onClickCapture: (e) => { if (dotHeld.current) { dotHeld.current = false; e.stopPropagation(); e.preventDefault(); } },
                children: jsxRuntimeExports.jsx(IndexHide, { contextId: 'share', hidden: indexHidden, onHiddenChange: setIndexHidden }),
            }),
            jsxRuntimeExports.jsx(MeasureTick, { value: textWidthEm, onSet: setTextWidthEm }),
            renderApp({
                device, onShareFolder: null, adminType: null, addDraft: null, adminVerified: false,
                instinctNavigation: null, axisKeep: bindAxis, axisLive: bindAxis, axisValues,
                pieceLayout: { hasOverride: false, onReset: () => setPieceLanes({ ...snapshotLanes.current }) },
                palette, setPalette, bg, bodyFace, layoutId, stepLayout, previewLayout, colorRef,
                commit: false, ctlOpen, doExport: () => {}, dropFace: () => {}, enterDraft: () => {},
                eraId: ERAS[2].id, exportAs: () => {}, faceOpen, focusDim, goToHit, hz, indexPt,
                leaveDraft: () => {}, lh, liveFolders: () => [SHARE_FOLDER], logoRoaming,
                mode: 'read', modePrefRef: { current: 'read' }, named: (f) => f, onCover: false,
                openFolder: scrollTop, openView: goHome, platen: false,
                resetDevice: () => {}, wipeDevice: () => {}, searchItems, setBg, setBodyFace,
                setCommit: () => {}, setCtlOpen, setEraId: () => {}, setFaceOpen, setFocusDim,
                setHz, setIndexPt, setInverted, setLh, setLogoRoaming, setOverlay: () => {},
                setPlaten: () => {}, setSoundOn: () => {}, setTaste, setTextPt, setTextWidthEm,
                setTitleFace, setView: () => {}, soundOn: false, syncJoined: () => {},
                syncRekeyed: () => {}, shareNotice: null, onShareNoticeDone: null, onShareNoticeCopied: null, textPt, textWidthEm, titleFace, uploadFace: () => {},
                uploads: [], view: SHARE_FOLDER.id, readOnly: true,
            }),
        ],
    });
}

/* ==========================================================================
 * main - entry point
 * --------------------------------------------------------------------------
 * Mounts the single <App /> component into #root. There is no router and no
 * host framework: the page is self-contained and makes no network calls beyond
 * its own files (fonts are inlined in fonts.css, audio sits next to index.html).
 * ========================================================================== */

// the door fetch starts here, after module evaluation: DOOR and FACES are module consts
// and a promise resumed mid-evaluation would touch them before they are born (the early
// start ran headlong into that - a silent, swallowed ReferenceError and an empty shelf)
const doorSettled = doorFaces();
await Promise.race([doorSettled, new Promise((r) => setTimeout(r, 2000))]); // the shelf can wait 2s, never more
/* a share link owns the page for a recipient: the read-only share view boots instead of
   the owner App - no login, no sync, no local state */
const shareMatch = parseShareHash(location.hash);
const rootEl = document.getElementById('root');
if (rootEl) createRoot(rootEl).render(
    shareMatch
        ? jsxRuntimeExports.jsx(ShareViewApp, { syncUrl: SYNC_URL, match: shareMatch })
        : jsxRuntimeExports.jsx(App, {}),
);



