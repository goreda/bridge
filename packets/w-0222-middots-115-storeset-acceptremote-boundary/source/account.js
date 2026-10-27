import { r as reactExports, j as jsxRuntimeExports } from './vendor.js?v=20261027-f7-held-keys-r1';
import { FOLDERS, clearPrivate } from './pieces.js?v=20261027-f7-held-keys-r1';
import { authMode, mailAction, consumeMailLink, changeCode, isJoined, isMagicProfile, bindEmail, dropGrant, join, leave, pushNow, wipeProfile, recoveryStatus, recoveryAcknowledge, loginDiag } from './sync.js?v=20261027-f7-held-keys-r1';
import { placePanel } from './draft.js?v=20261027-f7-held-keys-r1';
import { wipeRecovery, WipeRecoverySection } from './wipe-recovery.js?v=20261027-f7-held-keys-r1'; // r2: inline section inside this panel, no self-mounted fixed box

const PIN_MIN = 4;
const PIN_MAX = 4;
function PinField({ value, onChange, onEnter, label, shake, autoFocus = true, placeholder = '' }) {
    const [focused, setFocused] = reactExports.useState(false);
    const [shown, setShown] = reactExports.useState(-1);
    const [shaking, setShaking] = reactExports.useState(false);
    const inputRef = reactExports.useRef(null);
    reactExports.useEffect(() => { if (autoFocus) inputRef.current?.focus(); }, []);
    reactExports.useEffect(() => {
        if (!shake) return;
        setShaking(true);
        const t = window.setTimeout(() => setShaking(false), 380);
        return () => window.clearTimeout(t);
    }, [shake]);
    reactExports.useEffect(() => {
        if (shown < 0) return;
        const t = window.setTimeout(() => setShown(-1), 260);
        return () => window.clearTimeout(t);
    }, [shown, value]);
    const chars = Array.from(value); // by character, so an emoji or accented sign fills one box
    const boxes = Math.min(PIN_MAX, Math.max(PIN_MIN, chars.length + 1));
    const active = Math.min(chars.length, PIN_MAX - 1);
    return jsxRuntimeExports.jsxs('div', {
        className: `pin${shaking ? ' pin-shake' : ''}`,
        onClick: () => inputRef.current?.focus(),
        children: [
            jsxRuntimeExports.jsx('input', {
                ref: inputRef,
                className: 'pin-input',
                'aria-label': label,
                type: placeholder ? 'password' : 'text',
                autoComplete: 'off',
                autoCapitalize: 'off',
                autoCorrect: 'off',
                spellCheck: false,
                value: value,
                onFocus: () => setFocused(true),
                onBlur: () => setFocused(false),
                onKeyDown: (e) => {
                    if (e.key === 'Enter') {
                        e.preventDefault();
                        onEnter();
                    }
                },
                onChange: (e) => {
                    const v = Array.from(e.target.value.replace(/[\u0000-\u001f\u007f]/g, ''))
                        .slice(0, PIN_MAX)
                        .join('');
                    const n = Array.from(v).length;
                    setShown(n > Array.from(value).length ? n - 1 : -1); // only a freshly typed character shows
                    onChange(v);
                },
            }),
            jsxRuntimeExports.jsx('div', {
                className: 'pin-boxes',
                'aria-hidden': 'true',
                children: Array.from({ length: boxes }, (_, i) => {
                    const ch = chars[i];
                    const cls = [
                        'pin-box',
                        ch ? 'filled' : '',
                        focused && i === active && chars.length < PIN_MAX ? 'active' : '',
                    ].join(' ');
                    return jsxRuntimeExports.jsx(
                        'span',
                        {
                            className: cls,
                            children: ch
                                ? i === shown
                                    ? jsxRuntimeExports.jsx('span', {
                                          className: 'pin-char',
                                          children: ch,
                                      })
                                    : jsxRuntimeExports.jsx('span', {
                                          className: 'pin-dot',
                                          children: '\u00b7',
                                      })
                                : placeholder[i] || null,
                        },
                        i,
                    );
                }),
            }),
        ],
    });
}
/* a word set in the code field's boxes, one letter each (spaces become gaps): the panel's submit
   buttons wear it, so the action reads as part of the same row of little containers */
export function BoxWord({ word }) {
    return jsxRuntimeExports.jsx('span', {
        className: 'box-word',
        'aria-hidden': 'true',
        children: Array.from(word).map((ch, i) =>
            ch === ' '
                ? jsxRuntimeExports.jsx('span', { className: 'box-gap' }, i)
                : jsxRuntimeExports.jsx('span', { className: 'pin-box', children: ch }, i),
        ),
    });
}
const WORDS = {
    busy: '\u00b7\u00b7\u00b7\u00b7', // four middots: waiting on the service
    again: 'once', // type the new code once more
    mismatch: 'miss', // the two new codes differ
    moving: 'move', // the bucket is being moved to the new code
    done: 'done', // the code changed; other devices need the new one
    wait: 'wait', // too many misses from here; try again in a few minutes
    down: 'down', // the service did not answer
    taken: 'used', // the new code belongs to someone already
    other: 'nope',
};
function errorWord(error) {
    if (/^wait/.test(error)) return WORDS.wait;
    if (/did not answer/.test(error)) return WORDS.down;
    if (/taken|409/.test(error)) return WORDS.taken;
    return WORDS.other;
}
/* a state word, dimmed, in the boxes; its full meaning is spoken to screen readers */
const WORD_MEANING = {
    mail:'check your mail',
    [WORDS.busy]: 'working',
    [WORDS.again]: 'type the new code once more',
    [WORDS.mismatch]: 'the codes did not match',
    [WORDS.moving]: 'moving to the new code',
    [WORDS.done]: 'code changed; other devices need the new one',
    [WORDS.wait]: 'too many tries from here, wait a few minutes',
    [WORDS.down]: 'the sync service did not answer',
    [WORDS.taken]: 'that code is taken',
    [WORDS.other]: 'that did not work',
};
/* the one confirmation the panel speaks in plain English (the wipe-curtain voice): two lines,
   not a four-sign word. Every successful mail action lands here; the next action clears it. */
const MAIL_SENT = 'mail-sent';
export function SyncNote({ word }) {
    if (word === MAIL_SENT) {
        return jsxRuntimeExports.jsxs('p', {
            className: 'sync-note sync-mail-sent',
            role: 'status',
            children: ['mail sent', jsxRuntimeExports.jsx('br', {}), 'check your mail'],
        });
    }
    return jsxRuntimeExports.jsx('p', {
        className: 'sync-note sync-word',
        role: 'status',
        'aria-label': WORD_MEANING[word] ?? word,
        children: jsxRuntimeExports.jsx(BoxWord, { word: word }),
    });
}
/* r2 review-mountable real components: the sync panel uses the same ones it exports for the notice-review harness. */
export function SyncFlagDot() {
    return jsxRuntimeExports.jsx('span', { className: 'sync-flag-dot', 'aria-hidden': true });
}
export function SyncHeldRows({ records = [], broken = false, quota = false, onCopy = () => {}, onDownload = () => {} }) {
    const text = (r) => (r.title ? r.title + '\n' : '') + (r.lines || []).join('\n');
    return jsxRuntimeExports.jsxs('div', {
        className: 'sync-form sync-held',
        children: [
            broken && jsxRuntimeExports.jsx(SyncNote, { word: 'lost' }), // even the copy could not be kept
            broken && jsxRuntimeExports.jsxs('details', { className: 'sync-held-detail', children: [
                jsxRuntimeExports.jsx('summary', { children: 'what happened' }),
                jsxRuntimeExports.jsx('p', { className: 'sync-held-detail-text', children: 'this device could not keep a recovery copy - device storage refused the read. the piece itself is untouched; a copy may still be on the sync service.' }),
            ] }),
            quota && jsxRuntimeExports.jsx(SyncNote, { word: 'full' }), // device storage is full; copies are held elsewhere
            records.map((r) =>
                jsxRuntimeExports.jsxs('div', {
                    className: 'sync-held-row',
                    children: [
                        jsxRuntimeExports.jsx('span', { className: 'sync-held-title', children: r.title || '(untitled)' }),
                        jsxRuntimeExports.jsx('button', { type: 'button', className: 'face-choice box-submit', 'aria-label': 'copy the text', 'data-tip': 'copy the text', onClick: () => onCopy(text(r), r), children: jsxRuntimeExports.jsx(BoxWord, { word: 'copy' }) }),
                        jsxRuntimeExports.jsx('button', { type: 'button', className: 'face-choice box-submit', 'aria-label': 'download the text', 'data-tip': 'download the text', onClick: () => onDownload('middots-recovery-' + r.pieceId + '.txt', text(r), r), children: jsxRuntimeExports.jsx(BoxWord, { word: 'save' }) }),
                    ],
                }, r.pieceId)),
        ],
    });
}
/* task 7: the login attempt tuple lives on the admin/status surface (this panel), never the reading/draft canvas. */
export function DiagTuple({ diag }) {
    if (!diag || (!diag.config && !diag.join && !diag.state && !diag.admin)) return null;
    const leg = (label, v) => `${label} ${v || '\u2013'}`;
    const text = [leg('config', diag.config), leg('join', diag.join), leg('state', diag.state), leg('admin', diag.admin)].join(' \u00b7 ');
    return jsxRuntimeExports.jsx('p', { className: 'login-diag sync-diag', role: 'status', 'aria-label': text, children: text });
}

/* Taken-code visual only. Its trigger is deliberately not wired to /join yet:
   a new owner device and a stranger have identical server evidence today. */
function OccupiedHint({ visible }) {
    if (!visible) return null;
    return jsxRuntimeExports.jsxs('p', {
        className: 'sync-note sync-occupied-hint',
        role: 'status',
        'aria-label': 'type else',
        children: [
            jsxRuntimeExports.jsx('span', { children: 'type' }),
            jsxRuntimeExports.jsx('span', { children: 'else' }),
        ],
    });
}
function SyncControl({ onJoined, onLeft, onWiped, onRekeyed, onAdmin }) {
    const [open, setOpen] = reactExports.useState(false);
    const [code, setCode] = reactExports.useState('');
    const [email,setEmail]=reactExports.useState('');
    const [emailFlow,setEmailFlow]=reactExports.useState(false);
    const [authReady,setAuthReady]=reactExports.useState(false);
    const [first, setFirst] = reactExports.useState('');
    const [note, setNote] = reactExports.useState('');
    const [joined, setJoined] = reactExports.useState(isJoined());
    const [mode, setMode] = reactExports.useState('idle');
    const [wr, setWr] = reactExports.useState(wipeRecovery.state());
    reactExports.useEffect(() => { wipeRecovery.refresh(); return wipeRecovery.subscribe(setWr); }, []); // r2 fix: mount-time refresh, else a stored marker is invisible until a wipe event
    /* r2: recovery-copy facts ride the normal sync control - a quiet flag, rows inside the panel. */
    const [rec, setRec] = reactExports.useState(null);
    reactExports.useEffect(() => {
        let live = true;
        const refresh = () => void recoveryStatus().then(st => { if (live) setRec(st); });
        refresh();
        window.addEventListener('middots-recovery', refresh);
        return () => { live = false; window.removeEventListener('middots-recovery', refresh); };
    }, []);
    const recFlag = !!rec && (rec.broken || rec.quota || rec.unack > 0); // storage failure always flags; acknowledged copies stay quiet
    const [, diagBump] = reactExports.useState(0);
    reactExports.useEffect(() => {
        const on = () => diagBump((n) => n + 1);
        window.addEventListener('middots-login-diag', on);
        return () => window.removeEventListener('middots-login-diag', on);
    }, []);
    const copyText = (t) => { try { void navigator.clipboard?.writeText(t)?.catch(() => { }); } catch { } };
    const downloadText = (name, t) => {
        const u = URL.createObjectURL(new Blob([t], { type: 'text/plain' }));
        const a = document.createElement('a'); a.href = u; a.download = name; a.click();
        URL.revokeObjectURL(u);
    };
    const wrBlock = wr.status === 'block'; // a bound unknown marker suppresses every wipe control (ruling 3)
    const [shake, setShake] = reactExports.useState(0);
    const GRANT_MODES = ['bind-new', 'wipe-confirm'];
    /* the panel speaks only in four-sign words, set in the same boxes as the code: every state has
       one word (WORDS), never a sentence. The long meaning rides in aria-label for screen readers. */
    const nope = (word) => {
        setNote(word);
        setShake((n) => n + 1);
    };
    reactExports.useEffect(()=>{
        let live=true;
        void (async()=>{
            const link=await consumeMailLink();
            const capability=await authMode();
            if(!live)return;
            setEmailFlow(!!capability.email);setAuthReady(!capability.unavailable);
            if(link?.ok&&link.grant){setOpen(true);setMode(link.purpose==='wipe'?'wipe-confirm':'bind-new');setNote('');wipeRecovery.refresh();}
            else if(link?.ok&&link.changed){setOpen(true);setNote(WORDS.done);}
            else if(link?.ok){setJoined(true);window.dispatchEvent(new Event('middots-profile-change'));onJoined();}
            else if(link){setOpen(true);setNote(errorWord(link.error));}
        })();
        return ()=>{live=false;};
    },[]);
    const requestMail=async()=>{
        // only register still pairs a new code with the link; recover and rekey run on email alone
        const purpose=joined?'rekey':mode==='recover'?'recover':'register';
        const needsCode=purpose==='register';
        if(!email){nope(WORDS.other);return;}
        if(needsCode && Array.from(code).length!==4){nope(WORDS.other);return;}
        setNote(WORDS.busy);
        const r=await mailAction(purpose,needsCode?code:undefined,email);
        if(!r.ok){nope(errorWord(r.error));return;}
        setCode('');setEmail('');setFirst('');setMode('idle');
        if(!joined)onLeft(); // registration returns to the empty default page
        setNote(MAIL_SENT);
    };
    const go = async () => {
        if(!authReady)return;
        if(emailFlow && ['register','recover'].includes(mode))return requestMail();
        if (Array.from(code).length < PIN_MIN) {
            nope('');
            return;
        }
        setNote(WORDS.busy);
        const r = await join(code, true);
        if (r.ok) {
            setJoined(true);
            window.dispatchEvent(new Event('middots-profile-change'));
            setCode('');
            setNote('');
            // The verified profile exposes the admin door after the joined state is ready.
            onJoined();

            return;
        }
        nope(errorWord(r.error));
    };
    const next = async () => {
        if (Array.from(code).length < PIN_MIN) {
            nope('');
            return;
        }
        if (mode === 'new') {
            setFirst(code);
            setCode('');
            setMode('again');
            setNote(WORDS.again);
            return;
        }
        if (code !== first) {
            setCode('');
            setFirst('');
            setMode('new');
            nope(WORDS.mismatch);
            return;
        }
        if(emailFlow){setMode('rekey-mail');setNote('');return;}
        setMode('busy');
        setNote(WORDS.moving);
        const r = await changeCode(code, () => setNote(WORDS.moving));
        setCode('');
        setFirst('');
        if (!r.ok) {
            setMode('new');
            nope(errorWord(r.error));
            return;
        }
        await onRekeyed();
        setMode('idle');
        setNote(WORDS.done);
    };
    const wipe = async () => {
        if (mode !== 'wipe' || Array.from(code).length !== PIN_MIN) return;
        setMode('busy');
        setNote(WORDS.busy);
        if (isMagicProfile()) {
            // the verification mail comes first; nothing is deleted until its link is confirmed on the site
            const m = await mailAction('wipe', code);
            setCode('');
            if (!m.ok) { setMode('wipe'); nope(errorWord(m.error)); return; }
            setMode('idle');
            setNote(MAIL_SENT);
            return;
        }
        const g = await wipeRecovery.guardStart();
        if (!g.ok) { setMode('wipe'); setNote(''); return; } // plain message rides in the recovery notice region
        const r = await wipeProfile(code);
        setCode('');
        if (!r.ok) {
            if (r.unknown) wipeRecovery.unknown(); // O8: any non-typed outcome writes the marker
            setMode('wipe');
            nope(errorWord(r.error));
            return;
        }
        await wipeRecovery.applied();
        clearPrivate();
        window.dispatchEvent(new Event('middots-profile-change'));
        onWiped();
    };
    const swapMail = async () => {
        setNote(WORDS.busy);
        const r = await mailAction('email-old');
        if (!r.ok) { nope(errorWord(r.error)); return; }
        setNote(MAIL_SENT);
    };
    const bindNew = async () => {
        if (!email) return;
        setNote(WORDS.busy);
        const r = await bindEmail(email);
        if (!r.ok) { nope(errorWord(r.error)); return; }
        setEmail('');
        setMode('idle');
        setNote(MAIL_SENT);
    };
    const wipeNow = async () => {
        const g = await wipeRecovery.guardStart();
        if (!g.ok) { setMode('wipe-confirm'); setNote(''); return; }
        setMode('busy');
        setNote(WORDS.busy);
        const r = await wipeProfile(null, true);
        if (!r.ok) {
            if (r.unknown) wipeRecovery.unknown();
            setMode('wipe-confirm'); nope(errorWord(r.error)); return;
        }
        await wipeRecovery.applied();
        setJoined(false);
        clearPrivate();
        window.dispatchEvent(new Event('middots-profile-change'));
        setMode('idle');
        onWiped();
    };
    const cancel = () => {
        if (GRANT_MODES.includes(mode)) dropGrant();
        setMode('idle');
        setCode('');
        setFirst('');
        setEmail('');
        setNote('');
    };
    const panelRef = reactExports.useRef(null);
    // same placement as the type shelf, redone whenever the panel's content changes size
    reactExports.useEffect(() => {
        const list = panelRef.current;
        if (open && list && list.parentElement) placePanel(list, list.parentElement);
    }, [open, note, joined, mode, code.length]);
    reactExports.useEffect(() => {
        if (!open) return;
        const onDoc = (e) => {
            if (mode !== 'busy' && !GRANT_MODES.includes(mode) && !e.target.closest('.sync-widget')) setOpen(false);
        };
        const onKey = (e) => {
            if (e.key === 'Escape' && mode !== 'busy') setOpen(false);
        };
        document.addEventListener('mousedown', onDoc);
        document.addEventListener('keydown', onKey);
        return () => {
            document.removeEventListener('mousedown', onDoc);
            document.removeEventListener('keydown', onKey);
        };
    }, [open, mode]);
    // a closed panel forgets a half-typed code
    reactExports.useEffect(() => {
        if (!open && mode !== 'busy') {
            setCode('');
            setFirst('');
            if (mode !== 'idle' && !GRANT_MODES.includes(mode)) setMode('idle');
        }
    }, [open]);
    const label = joined ? 'synced' : 'sync';
    return jsxRuntimeExports.jsxs('div', {
        className: 'face-widget sync-widget',
        children: [
            open &&
                jsxRuntimeExports.jsxs('div', {
                    className: 'face-list sync-panel',
                    ref: panelRef,
                    children: [
                        wr.status !== 'none' && jsxRuntimeExports.jsx(WipeRecoverySection, {}),
                        jsxRuntimeExports.jsx(DiagTuple, { diag: loginDiag() }),
                        joined &&
                            (mode === 'idle' || mode === 'wipe') &&
                            jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, {
                                children: [
                                    note && jsxRuntimeExports.jsx(SyncNote, { word: note }),
                                    jsxRuntimeExports.jsx('button', {
                                        type: 'button',
                                        className: 'face-choice box-submit sync-menu-item',
                                        'aria-label': 'change code', 'data-tip': 'change code',
                                        onClick: () => {
                                            setMode('new');
                                            setNote('');
                                        },
                                        children: [
                                            jsxRuntimeExports.jsx(BoxWord, { word: 'edit' }),
                                            jsxRuntimeExports.jsx(BoxWord, { word: 'code' }),
                                        ],
                                    }),
                                    emailFlow && isMagicProfile() &&
                                        jsxRuntimeExports.jsx('button', {
                                            type: 'button',
                                            className: 'face-choice box-submit sync-menu-item',
                                            'aria-label': 'change e-mail', 'data-tip': 'change e-mail',
                                            onClick: () => void swapMail(),
                                            children: jsxRuntimeExports.jsx(BoxWord, { word: 'swap' }),
                                        }),
                                    jsxRuntimeExports.jsx('button', {
                                        type: 'button',
                                        className: 'face-choice box-submit sync-menu-item',
                                        'aria-label': 'leave', 'data-tip': 'leave',
                                        onClick: async () => {
                                            // leaving resets this device to a fresh page, at once: nothing is lost, it all stays
                                            // on the code, and joining again brings it back
                                            await pushNow();
                                            leave();
                                            window.dispatchEvent(new Event('middots-profile-change'));
                                            clearPrivate();
                                            onLeft();
                                        },
                                        children: jsxRuntimeExports.jsx(BoxWord, { word: 'exit' }),
                                    }),
                                    !wrBlock && jsxRuntimeExports.jsx('button', {
                                        type: 'button',
                                        className: 'face-choice box-submit sync-wipe sync-quiet sync-menu-item',
                                        'aria-label': 'wipe profile content', 'data-tip': isMagicProfile() ? 'wipe by mail' : 'wipe profile',
                                        onClick: () => mode === 'wipe' ? cancel() : (setMode('wipe'), setCode(''), setNote('')),
                                        children: jsxRuntimeExports.jsx(BoxWord, { word: 'wipe' }),
                                    }),
                                    rec && (rec.records.length > 0 || rec.broken || rec.quota) && jsxRuntimeExports.jsxs('button', {
                                        type: 'button',
                                        className: 'face-choice box-submit sync-menu-item',
                                        'aria-label': 'held recovery copies', 'data-tip': 'held recovery copies',
                                        onClick: () => { setMode('held'); setNote(''); void recoveryAcknowledge(); }, // seeing the rows acknowledges them once
                                        children: [
                                            jsxRuntimeExports.jsx(BoxWord, { word: 'held' }),
                                            rec.unack > 0 && jsxRuntimeExports.jsx('span', { className: 'sync-flag-dot', 'aria-hidden': true }),
                                        ],
                                    }),
                                ],
                            }),
                        joined && mode === 'held' &&
                            jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, {
                                children: [
                                    jsxRuntimeExports.jsx(SyncHeldRows, { records: rec?.records ?? [], broken: !!rec?.broken, quota: !!rec?.quota, onCopy: (t) => copyText(t), onDownload: (n, t) => downloadText(n, t) }),
                                    jsxRuntimeExports.jsx('button', {
                                        type: 'button', className: 'face-choice box-submit', 'aria-label': 'back', 'data-tip': 'go back',
                                        onClick: cancel,
                                        children: jsxRuntimeExports.jsx(BoxWord, { word: 'back' }),
                                    }),
                                ],
                            }),
                        !wrBlock && mode === 'wipe-confirm' &&
                            jsxRuntimeExports.jsxs('div', {
                                className: 'sync-form',
                                children: [
                                    jsxRuntimeExports.jsx('button', {
                                        type: 'button', className: 'face-choice box-submit sync-wipe',
                                        'aria-label': 'wipe this shelf for good', 'data-tip': 'wipe now',
                                        onClick: () => void wipeNow(),
                                        children: jsxRuntimeExports.jsx(BoxWord, { word: 'WIPE' }),
                                    }),
                                    note && jsxRuntimeExports.jsx(SyncNote, { word: note }),
                                    jsxRuntimeExports.jsx('button', {
                                        type: 'button', className: 'face-choice box-submit', 'aria-label': 'back', 'data-tip': 'go back',
                                        onClick: cancel, children: jsxRuntimeExports.jsx(BoxWord, { word: 'back' }),
                                    }),
                                ],
                            }),
                        mode === 'bind-new' &&
                            jsxRuntimeExports.jsxs('form', {
                                className: 'sync-form',
                                onSubmit: (e) => { e.preventDefault(); void bindNew(); },
                                children: [
                                    jsxRuntimeExports.jsxs('span', { children: [jsxRuntimeExports.jsx(BoxWord, { word: 'new' }), jsxRuntimeExports.jsx(BoxWord, { word: 'mail' })] }),
                                    jsxRuntimeExports.jsx('input', { type: 'email', className: 'sync-email', value: email, onChange: (e) => setEmail(e.target.value), 'aria-label': 'new e-mail', autoComplete: 'email', required: true }),
                                    jsxRuntimeExports.jsx('button', { type: 'submit', className: 'face-choice box-submit', 'aria-label': 'send link', 'data-tip': 'send link', disabled: !email, children: jsxRuntimeExports.jsx(BoxWord, { word: 'mail' }) }),
                                    jsxRuntimeExports.jsx('button', { type: 'button', className: 'face-choice box-submit', 'aria-label': 'back', 'data-tip': 'go back', onClick: cancel, children: jsxRuntimeExports.jsx(BoxWord, { word: 'back' }) }),
                                    note && jsxRuntimeExports.jsx(SyncNote, { word: note }),
                                ],
                            }),
                        joined && !wrBlock && mode === 'wipe' &&
                            jsxRuntimeExports.jsxs('form', {
                                className: 'sync-form',
                                onSubmit: (e) => { e.preventDefault(); void wipe(); },
                                children: [
                                    jsxRuntimeExports.jsx(PinField, {
                                        value: code, onChange: (v) => { setCode(v); setNote(''); },
                                        onEnter: () => void wipe(), label: 'code to confirm wipe', shake,
                                    }),
                                    note && jsxRuntimeExports.jsx(SyncNote, { word: note }),
                                    jsxRuntimeExports.jsx('button', {
                                        type: 'submit', className: 'face-choice box-submit sync-wipe',
                                        'aria-label': 'sure, wipe this shelf', 'data-tip': 'are you?',
                                        disabled: Array.from(code).length !== PIN_MIN,
                                        children: jsxRuntimeExports.jsx(BoxWord, { word: Array.from(code).length === PIN_MIN ? 'SURE' : 'sure' }),
                                    }),
                                ],
                            }),
                        joined && mode === 'rekey-mail' && jsxRuntimeExports.jsxs('form',{className:'sync-form',onSubmit:e=>{e.preventDefault();void requestMail();},children:[
                            jsxRuntimeExports.jsx('input',{type:'email',className:'sync-email',value:email,onChange:e=>setEmail(e.target.value),'aria-label':'bound email',autoComplete:'email',required:true}),
                            jsxRuntimeExports.jsx('button',{type:'submit',className:'face-choice box-submit','data-tip':'send link',disabled:!email,children:jsxRuntimeExports.jsx(BoxWord,{word:'mail'})}),
                            jsxRuntimeExports.jsx('button',{type:'button',className:'face-choice box-submit','data-tip':'go back',onClick:cancel,children:jsxRuntimeExports.jsx(BoxWord,{word:'back'})}),
                            note && jsxRuntimeExports.jsx(SyncNote,{word:note}),
                        ]}),
                        joined && mode !== 'idle' && mode !== 'wipe' && mode !== 'held' && mode !== 'rekey-mail' && !GRANT_MODES.includes(mode) && mode !== 'busy-mail' &&
                            jsxRuntimeExports.jsxs('form', {
                                className: 'sync-form',
                                onSubmit: (e) => {
                                    e.preventDefault();
                                    if (mode !== 'busy') void next();
                                },
                                children: [
                                    mode !== 'busy' &&
                                        jsxRuntimeExports.jsx(
                                            PinField,
                                            {
                                                value: code,
                                                onChange: (v) => {
                                                    setCode(v);
                                                },
                                                onEnter: () => void next(),
                                                label: mode === 'new' ? 'new code' : 'new code again',
                                                shake: shake,
                                            },
                                            mode,
                                        ),
                                    note && jsxRuntimeExports.jsx(SyncNote, { word: note }),
                                    mode !== 'busy' &&
                                        jsxRuntimeExports.jsxs('div', {
                                            className: 'sync-actions',
                                            children: [
                                                jsxRuntimeExports.jsx('button', {
                                                    type: 'button',
                                                    className: 'face-choice box-submit',
                                                    'aria-label': 'back', 'data-tip': 'go back',
                                                    onClick: cancel,
                                                    children: jsxRuntimeExports.jsx(BoxWord, {
                                                        word: 'back',
                                                    }),
                                                }),
                                                jsxRuntimeExports.jsx('button', {
                                                    type: 'submit',
                                                    className: 'face-choice box-submit',
                                                    'aria-label': mode === 'new' ? 'next' : 'change code', 'data-tip': mode === 'new' ? 'next step' : 'save code',
                                                    disabled: Array.from(code).length < PIN_MIN,
                                                    children: jsxRuntimeExports.jsx(BoxWord, {
                                                        word: mode === 'new' ? 'next' : 'save',
                                                    }),
                                                }),
                                            ],
                                        }),
                                ],
                            }),
                        !joined && !GRANT_MODES.includes(mode) &&
                            jsxRuntimeExports.jsxs('form', {
                                className: 'sync-form',
                                onSubmit: (e) => {
                                    e.preventDefault();
                                    void go();
                                },
                                children: [
                                    mode !== 'recover' && jsxRuntimeExports.jsx(PinField, {
                                        value: code,
                                        onChange: (v) => {
                                            setCode(v);
                                            setNote('');
                                        },
                                        onEnter: () => void go(),
                                        label: 'sync code',
                                        shake: shake,
                                    }),
                                    emailFlow && mode !== 'idle' && jsxRuntimeExports.jsx('input',{type:'email',className:'sync-email',value:email,onChange:e=>setEmail(e.target.value),'aria-label':'email',autoComplete:'email',required:true}),
                                    jsxRuntimeExports.jsx('button', {
                                        type: 'submit',
                                        className: 'face-choice box-submit',
                                        'aria-label': emailFlow && mode !== 'idle' ? 'check your mail' : 'sync', 'data-tip': emailFlow && mode !== 'idle' ? 'send link' : 'sync',
                                        disabled: !authReady || (mode === 'recover' ? !email : Array.from(code).length < PIN_MIN || (emailFlow && mode !== 'idle' && !email)),
                                        children: jsxRuntimeExports.jsx(BoxWord, {
                                            word: emailFlow && mode !== 'idle' ? 'mail' : 'sync',
                                        }),
                                    }),
                                    emailFlow && jsxRuntimeExports.jsxs('div',{className:'sync-actions',children:mode==='idle' ? [
                                        jsxRuntimeExports.jsx('button',{type:'button',className:'face-choice box-submit','data-tip':'lost code',onClick:()=>{setMode('recover');setNote('');},children:jsxRuntimeExports.jsx(BoxWord,{word:'lost'})}),
                                        jsxRuntimeExports.jsx('button',{type:'button',className:'face-choice box-submit','data-tip':'new profile',onClick:()=>{setMode('register');setNote('');},children:jsxRuntimeExports.jsx(BoxWord,{word:'new?'})}),
                                    ]:[
                                        mode !== 'recover' && jsxRuntimeExports.jsx('span',{children:[jsxRuntimeExports.jsx(BoxWord,{word:'new'}),jsxRuntimeExports.jsx(BoxWord,{word:'code'})]}),
                                        jsxRuntimeExports.jsx('button',{type:'button',className:'face-choice box-submit','data-tip':'go back',onClick:cancel,children:jsxRuntimeExports.jsx(BoxWord,{word:'back'})}),
                                    ]}),
                                    note && jsxRuntimeExports.jsx(SyncNote, { word: note }),
                                ],
                            }),
                    ],
                }),
            jsxRuntimeExports.jsx('button', {
                type: 'button',
                className: (open ? 'on' : '') + (recFlag || (wr.status !== 'none' && wr.status !== 'disabled') ? ' sync-flag' : ''),
                'aria-label': label,
                'data-tip': open ? undefined : label,
                'aria-expanded': open,
                onClick: () => setOpen(!open),
                children: jsxRuntimeExports.jsxs('svg', {
                    width: '14',
                    height: '14',
                    viewBox: '0 0 14 14',
                    'aria-hidden': 'true',
                    children: [
                        jsxRuntimeExports.jsx('path', {
                            d: 'M2.4 6.2a4.7 4.7 0 0 1 8.3-2.1M11.6 7.8a4.7 4.7 0 0 1-8.3 2.1',
                            fill: 'none',
                            stroke: 'currentColor',
                            strokeWidth: '1.1',
                        }),
                        jsxRuntimeExports.jsx('path', {
                            d: 'M10.9 1.9v2.4H8.5M3.1 12.1V9.7h2.4',
                            fill: 'none',
                            stroke: 'currentColor',
                            strokeWidth: '1.1',
                        }),
                        joined &&
                            jsxRuntimeExports.jsx('circle', {
                                cx: '7',
                                cy: '7',
                                r: '1.1',
                                fill: 'currentColor',
                            }),
                    ],
                }),
            }),
        ],
    });
}
/* '#/<folder>' in the address -> that folder's id; null for anything else */
function viewFromHash(own = []) {
    const m = location.hash.match(/^#\/(.+)$/);
    const id = m ? decodeURIComponent(m[1]) : '';
    if (id === 'instinct') return id; // private bridge; the server checks the current admin
    if (id === 'admin/tango') return 'admin/logo'; // old saved route
    if (id === 'admin/mailing' || id === 'admin/audio' || id === 'admin/logo' || id === 'admin' || id === 'admin/edit' || id === 'admin/changes' || id === 'admin/history') return id; // the admin pages: not folders, they resolve for anyone - the token does the rest
    return [...FOLDERS, ...own].some((f) => f.id === id) ? id : null;
}
/* folders made on the page, as found in a saved state: only well-formed {id, title} entries */
function readFolders(v) {
    if (!Array.isArray(v)) return [];
    return v.filter(
        (f) =>
            !!f && typeof f.id === 'string' && typeof f.title === 'string' && f.id.startsWith('f-'),
    );
}

export { OccupiedHint, SyncControl, readFolders, viewFromHash };
