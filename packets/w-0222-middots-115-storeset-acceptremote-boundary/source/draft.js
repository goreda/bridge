import { r as reactExports, j as jsxRuntimeExports, R as React } from './vendor.js?v=20261027-f7-held-keys-r1';
import { PIECES } from './pieces.js?v=20261027-f7-held-keys-r1';
import { classifyKeydown, playSound, warmAudio } from './audio.js?v=20261027-f7-held-keys-r1';
import { AudioPart, audioAt } from './audio-part.js?v=20261027-f7-held-keys-r1';
import { whenSealed, whenCells, useStackedHead, sameLines, stripZw } from './controls.js?v=20261027-f7-held-keys-r1';
import { typeInto } from './tip-type.js?v=20261027-f7-held-keys-r1';
import { unit as randomUnit } from './random.js?v=20261027-f7-held-keys-r1';

const ERA_TIPS = {
    iron: '1900s heavy standard',
    noiseless: '1930s noiseless',
    portable: '1950s portable',
    electric: '1970s electric',
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

/* ---- typing sound hook ---------------------------------------------------
 * Attaches keydown -> playSound to an editable element once.
 */
function attachTypeSound(el, pref) {
    if (!el || el.__wtSound) return;
    el.__wtSound = true;
    let lastKeydown = 0;
    el.addEventListener('keydown', (e) => {
        const s = pref.current;
        if (!s.on) return;
        const k = classifyKeydown(e); // no isComposing early-return: phone keyboards compose every letter
        if (k) { lastKeydown = performance.now(); playSound(s.era, k); }
    });
    // soft keyboards (Android: key 'Unidentified', keyCode 229; iOS predictive text) send no usable letter keydown.
    // beforeinput carries what was typed; skipped when a keydown just sounded (desktop, or Enter/Backspace on phones).
    el.addEventListener('beforeinput', (e) => {
        const s = pref.current;
        if (!s.on || performance.now() - lastKeydown < 60) return;
        const t = e.inputType;
        if (t === 'insertText' || t === 'insertCompositionText' || t === 'insertReplacementText')
            playSound(s.era, e.data === ' ' ? 'space' : 'key');
        else if (t === 'insertParagraph' || t === 'insertLineBreak') playSound(s.era, 'return');
        else if (t && t.startsWith('delete')) playSound(s.era, 'delete');
    });
    el.addEventListener('focus', () => warmAudio());
}
/* ---- text model: paragraphs as strings; soft line breaks are \n inside a paragraph;
   overstruck runs (commitment mode) are wrapped in U+E000 ... U+E001 ---- */
const OV_OPEN = '\uE000';
const OV_CLOSE = '\uE001';
const BLOCK = /^(P|DIV|LI|H[1-6]|BLOCKQUOTE|PRE)$/;
/* hand formatting rides the same way: italic E002..E003, bold E004..E005, underline E006..E007,
   strikethrough E008..E009 (a chosen strike, separate from commitment mode's overstrike) */
const FX = [
    { key: 'i', tag: 'EM', open: '\uE002', close: '\uE003' },
    { key: 'b', tag: 'STRONG', open: '\uE004', close: '\uE005' },
    { key: 'u', tag: 'U', open: '\uE006', close: '\uE007' },
    { key: 's', tag: 'DEL', open: '\uE008', close: '\uE009' },
];
const FX_TAG = {
    EM: ['\uE002', '\uE003'],
    I: ['\uE002', '\uE003'],
    STRONG: ['\uE004', '\uE005'],
    B: ['\uE004', '\uE005'],
    U: ['\uE006', '\uE007'],
    DEL: ['\uE008', '\uE009'],
    S: ['\uE008', '\uE009'],
    STRIKE: ['\uE008', '\uE009'],
};
function readInline(node) {
    let out = '';
    node.childNodes.forEach((c) => {
        if (c.nodeType === 3) out += stripZw(c.data.replace(/\u00a0/g, ' '));
        else if (c.nodeName === 'BR') out += '\n';
        else if (c instanceof HTMLElement && c.classList.contains('ov')) {
            const inner = readInline(c).replace(/[\uE000\uE001]/g, '');
            if (inner) out += OV_OPEN + inner + OV_CLOSE;
        } else if (c instanceof HTMLElement && FX_TAG[c.nodeName] && !c.classList.contains('ov')) {
            const [o, cl] = FX_TAG[c.nodeName];
            const inner = readInline(c);
            if (inner.replace(/[\uE000-\uE009]/g, '')) out += o + inner + cl;
        } else out += readInline(c);
    });
    return out;
}
/* reads an editable body back into paragraphs exactly as they sit on screen:
   every block is a paragraph (empty ones included), <br> and newline text are soft breaks */
function readParas(root) {
    const paras = [];
    let loose = null;
    const flushLoose = () => {
        if (loose !== null) {
            paras.push(loose);
            loose = null;
        }
    };
    root.childNodes.forEach((c) => {
        if (c.nodeType === 1 && c.hasAttribute('data-audio-part')) return;
        if (c.nodeType === 1 && BLOCK.test(c.nodeName)) {
            flushLoose();
            paras.push(readInline(c));
        } else {
            const t =
                c.nodeType === 3
                    ? stripZw(c.data.replace(/\u00a0/g, ' '))
                    : c.nodeName === 'BR'
                      ? '\n'
                      : readInline(c);
            loose = (loose ?? '') + t;
        }
    });
    flushLoose();
    // an empty block that only holds its placeholder <br> is an empty paragraph
    return paras.map((p) =>
        p === '\n'
            ? ''
            : p
                  .replace(/\uE000\uE001/g, '')
                  .replace(/\uE001\uE000/g, '')
                  .replace(/\uE002\uE003|\uE004\uE005|\uE006\uE007|\uE008\uE009/g, '')
                  .replace(/\uE003\uE002/g, '')
                  .replace(/\uE005\uE004/g, '')
                  .replace(/\uE007\uE006/g, '')
                  .replace(/\uE009\uE008/g, ''),
    );
}
function readTitle(el) {
    // Enter in the title makes <p> blocks; their texts have no separator in textContent, so the
    // lines ran together ("First linesecond"). Join the non-empty blocks with one space.
    const blocks = [...el.childNodes].filter((n) => n.nodeType === 1 && /^(P|DIV)$/.test(n.nodeName));
    const raw = blocks.length
        ? [...el.childNodes].map((n) => n.textContent || '').filter((t) => t !== '').join('\n')
        : el.textContent || '';
    // A line break is kept as one "\n" (stored, reloaded, rendered with pre-line); other spacing is untouched.
    return stripZw(raw).replace(/\u00a0/g, ' ').replace(/[ \t]*\n[ \t\n]*/g, '\n').replace(/^\n+|\n+$/g, '');
}
/* renders a paragraph string with its marks as nested elements (marks nest properly: they were read off a DOM tree) */
function ParaText({ text }) {
    if (!/[\uE000-\uE009]/.test(text))
        return jsxRuntimeExports.jsx(jsxRuntimeExports.Fragment, {
            children: text,
        });
    let i = 0;
    let k = 0;
    const walk = (closer) => {
        const out = [];
        let buf = '';
        const flush = () => {
            if (buf) {
                out.push(jsxRuntimeExports.jsx(React.Fragment, { children: buf }, k++));
                buf = '';
            }
        };
        while (i < text.length) {
            const ch = text[i];
            if (closer !== null && ch === closer) {
                i++;
                flush();
                return out;
            }
            if (ch === OV_OPEN) {
                i++;
                flush();
                out.push(
                    jsxRuntimeExports.jsx('s', { className: 'ov', children: walk(OV_CLOSE) }, k++),
                );
                continue;
            }
            const fx = FX.find((f) => f.open === ch);
            if (fx) {
                i++;
                flush();
                const kids = walk(fx.close);
                out.push(
                    fx.key === 'i'
                        ? jsxRuntimeExports.jsx('em', { children: kids }, k++)
                        : fx.key === 'b'
                          ? jsxRuntimeExports.jsx('strong', { children: kids }, k++)
                          : fx.key === 'u'
                            ? jsxRuntimeExports.jsx('u', { children: kids }, k++)
                            : jsxRuntimeExports.jsx('del', { children: kids }, k++),
                );
                continue;
            }
            if (/[\uE000-\uE009]/.test(ch)) {
                i++;
                continue;
            } // a stray closer
            buf += ch;
            i++;
        }
        flush();
        return out;
    };
    return jsxRuntimeExports.jsx(jsxRuntimeExports.Fragment, {
        children: walk(null),
    });
}

/* ---- hand formatting -----------------------------------------------------
 * Italic / bold / underline / strikethrough applied to a selection by wrapping
 * or lifting text nodes. The palette appears after a short rest on a selection.
 */
function fxAncestor(n, root, tag) {
    const tags = Object.keys(FX_TAG).filter((t) => FX_TAG[t][0] === FX_TAG[tag][0]);
    while (n && n !== root) {
        if (n instanceof HTMLElement && tags.includes(n.nodeName) && !n.classList.contains('ov'))
            return n;
        n = n.parentNode;
    }
    return null;
}
/* text nodes inside the range, split so each one lies wholly within it */
function rangeTextNodes(root, range) {
    const nodes = textNodesIn(root).filter((t) => range.intersectsNode(t) && t.data.length);
    const out = [];
    nodes.forEach((t) => {
        let node = t;
        const from = node === range.startContainer ? range.startOffset : 0;
        const to = node === range.endContainer ? range.endOffset : node.data.length;
        if (from >= to) return;
        if (to < node.data.length) node.splitText(to);
        if (from > 0) node = node.splitText(from);
        out.push(node);
    });
    return out;
}
/* pull one text node out of a formatting ancestor, splitting the ancestor around it */
function liftOut(node, anc) {
    const before = document.createRange();
    before.setStart(anc, 0);
    before.setEndBefore(node);
    const pre = before.extractContents();
    if (pre.textContent) {
        const c = anc.cloneNode(false);
        c.appendChild(pre);
        anc.before(c);
    }
    const after = document.createRange();
    after.setStartAfter(node);
    after.setEnd(anc, anc.childNodes.length);
    const post = after.extractContents();
    if (post.textContent) {
        const c = anc.cloneNode(false);
        c.appendChild(post);
        anc.after(c);
    }
    while (anc.firstChild) anc.before(anc.firstChild);
    anc.remove();
}
function fxState(root, range, tag) {
    const nodes = textNodesIn(root).filter((t) => range.intersectsNode(t) && t.data.trim().length);
    return nodes.length > 0 && nodes.every((t) => fxAncestor(t, root, tag));
}
function toggleFx(root, tag) {
    const sel = window.getSelection();
    if (!sel || !sel.rangeCount) return;
    const range = sel.getRangeAt(0);
    if (range.collapsed || !root.contains(range.commonAncestorContainer)) return;
    const on = fxState(root, range, tag);
    const nodes = rangeTextNodes(root, range);
    if (!nodes.length) return;
    nodes.forEach((t) => {
        if (on) {
            let a = fxAncestor(t, root, tag);
            while (a) {
                liftOut(t, a);
                a = fxAncestor(t, root, tag);
            }
        } else if (!fxAncestor(t, root, tag)) {
            const w = document.createElement(tag.toLowerCase());
            t.before(w);
            w.appendChild(t);
        }
    });
    // merge touching twins so the marks stay tidy
    root.querySelectorAll('em, strong, u, del').forEach((el) => {
        const next = el.nextSibling;
        if (
            next instanceof HTMLElement &&
            next.nodeName === el.nodeName &&
            !next.classList.contains('ov')
        ) {
            while (next.firstChild) el.appendChild(next.firstChild);
            next.remove();
        }
    });
    const nr = document.createRange();
    nr.setStartBefore(nodes[0]);
    nr.setEndAfter(nodes[nodes.length - 1]);
    sel.removeAllRanges();
    sel.addRange(nr);
    root.dispatchEvent(new Event('input', { bubbles: true }));
}
/* the style palette: rises near a selection in a draft body after a short rest */
function FxPalette() {
    const [pos, setPos] = reactExports.useState(null);
    const [, bump] = reactExports.useState(0);
    const timer = reactExports.useRef(undefined);
    const hovering = reactExports.useRef(false);
    reactExports.useEffect(() => {
        const check = () => {
            window.clearTimeout(timer.current);
            const sel = window.getSelection();
            const r = sel && sel.rangeCount ? sel.getRangeAt(0) : null;
            const host =
                r && !r.collapsed
                    ? (r.commonAncestorContainer.nodeType === 1
                          ? r.commonAncestorContainer
                          : r.commonAncestorContainer.parentElement
                      )?.closest('.story-text.editable')
                    : null;
            if (!r || !host) {
                if (!hovering.current) setPos(null);
                return;
            }
            timer.current = window.setTimeout(() => {
                const now = window.getSelection();
                if (!now || now.toString() !== sel.toString()) return; // the rest belongs to this selection only
                const rects = r.getClientRects();
                const first = rects[0] ?? r.getBoundingClientRect();
                const box = r.getBoundingClientRect();
                setPos({
                    x: Math.max(8, Math.min(first.left, window.innerWidth - 220)),
                    y: box.top,
                    root: host,
                });
            }, 450);
        };
        document.addEventListener('selectionchange', check);
        const onScroll = () => {
            if (!hovering.current) setPos(null);
        };
        window.addEventListener('scroll', onScroll, true);
        return () => {
            document.removeEventListener('selectionchange', check);
            window.removeEventListener('scroll', onScroll, true);
            window.clearTimeout(timer.current);
        };
    }, []);
    if (!pos) return null;
    const sel = window.getSelection();
    const r = sel && sel.rangeCount ? sel.getRangeAt(0) : null;
    const above = pos.y > 52;
    return jsxRuntimeExports.jsxs('div', {
        className: 'fx-palette',
        style: { left: pos.x, top: above ? pos.y - 40 : pos.y + 28 },
        onMouseEnter: () => {
            hovering.current = true;
        },
        onMouseLeave: () => {
            hovering.current = false;
        },
        onMouseDown: (e) => e.preventDefault(),
        children: [
            FX.map((f) =>
                jsxRuntimeExports.jsx(
                    'button',
                    {
                        type: 'button',
                        'aria-label': {
                            i: 'italic',
                            b: 'bold',
                            u: 'underline',
                            s: 'strikethrough',
                        }[f.key],
                        className: `fx-${f.key}${r && fxState(pos.root, r, f.tag) ? ' on' : ''}`,
                        onClick: () => {
                            toggleFx(pos.root, f.tag);
                            bump((n) => n + 1);
                        },
                        children:
                            f.key === 'i'
                                ? jsxRuntimeExports.jsx('em', { children: 'i' })
                                : f.key === 'b'
                                  ? jsxRuntimeExports.jsx('strong', { children: 'b' })
                                  : f.key === 'u'
                                    ? jsxRuntimeExports.jsx('u', { children: 'u' })
                                    : jsxRuntimeExports.jsx('del', { children: 's' }),
                    },
                    f.key,
                ),
            ),
            jsxRuntimeExports.jsx('span', {
                className: 'fx-sep',
                'aria-hidden': 'true',
            }),
            jsxRuntimeExports.jsx('button', {
                type: 'button',
                'aria-label': 'outdent',
                className: 'fx-outdent',
                onClick: () => {
                    tabKey(pos.root, true);
                    bump((n) => n + 1);
                },
                children: '\u21e4',
            }),
            jsxRuntimeExports.jsx('button', {
                type: 'button',
                'aria-label': 'indent',
                className: 'fx-indent',
                onClick: () => {
                    tabKey(pos.root, false);
                    bump((n) => n + 1);
                },
                children: '\u21e5',
            }),
        ],
    });
}


/* ---- commitment mode -----------------------------------------------------
 * Deleting strikes text through instead of removing it. These helpers walk,
 * split and merge the <s class="ov"> runs while keeping the caret in place.
 */
function ovAncestor(n, root) {
    while (n && n !== root) {
        if (n instanceof HTMLElement && n.classList.contains('ov')) return n;
        n = n.parentNode;
    }
    return null;
}
function textNodesIn(root) {
    const out = [];
    const w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    let n;
    while ((n = w.nextNode())) out.push(n);
    return out;
}
function wrapOv(root, node, from, to) {
    if (ovAncestor(node, root) || from >= to) return;
    let target = node;
    if (from > 0) target = target.splitText(from);
    if (to - from < target.data.length) target.splitText(to - from);
    const s = document.createElement('s');
    s.className = 'ov';
    target.parentNode.insertBefore(s, target);
    s.appendChild(target);
}
function mergeOv(root) {
    root.querySelectorAll('s.ov').forEach((el) => {
        const next = el.nextSibling;
        if (next instanceof HTMLElement && next.classList.contains('ov')) {
            while (next.firstChild) el.appendChild(next.firstChild);
            next.remove();
        }
        if (!el.textContent) el.remove();
    });
    root.querySelectorAll('s.ov').forEach((el) => el.normalize());
}
/* strike every unstruck character inside a range */
function strikeRange(root, range) {
    const nodes = textNodesIn(root).filter((t) => range.intersectsNode(t));
    nodes.forEach((t) => {
        const from = t === range.startContainer ? range.startOffset : 0;
        const to = t === range.endContainer ? range.endOffset : t.data.length;
        wrapOv(root, t, from, to);
    });
    mergeOv(root);
}
/* backspace on paper: the nearest unstruck characters before the caret get struck,
   the carriage stays where it was */
function strikeBack(root, caret, word, forward) {
    const nodes = textNodesIn(root);
    // flatten unstruck positions in document order
    const pos = [];
    nodes.forEach((t) => {
        if (!ovAncestor(t, root)) for (let i = 0; i < t.data.length; i++) pos.push({ t, i });
    });
    const before = (p) => {
        const r = document.createRange();
        r.setStart(p.t, p.i);
        return r.compareBoundaryPoints(Range.START_TO_START, caret) < 0;
    };
    let idx;
    if (!forward) {
        idx = -1;
        for (let k = pos.length - 1; k >= 0; k--)
            if (before(pos[k])) {
                idx = k;
                break;
            }
        if (idx < 0) return;
        let lo = idx;
        if (word) {
            while (lo > 0 && /\s/.test(pos[lo].t.data[pos[lo].i])) lo--;
            while (lo > 0 && !/\s/.test(pos[lo - 1].t.data[pos[lo - 1].i])) lo--;
        }
        for (let k = idx; k >= lo; k--) wrapOv(root, pos[k].t, pos[k].i, pos[k].i + 1);
    } else {
        idx = pos.findIndex((p) => !before(p));
        if (idx < 0) return;
        let hi = idx;
        if (word) {
            while (hi < pos.length - 1 && /\s/.test(pos[hi].t.data[pos[hi].i])) hi++;
            while (hi < pos.length - 1 && !/\s/.test(pos[hi + 1].t.data[pos[hi + 1].i])) hi++;
        }
        for (let k = hi; k >= idx; k--) wrapOv(root, pos[k].t, pos[k].i, pos[k].i + 1);
    }
    mergeOv(root);
}
/* caret after a struck run: new letters must land outside the strike */
function caretOutsideOv(root) {
    const sel = window.getSelection();
    if (!sel || !sel.rangeCount) return false;
    const r = sel.getRangeAt(0);
    const ov = ovAncestor(r.startContainer, root);
    if (ov) {
        const after = document.createRange();
        after.setStartAfter(ov);
        after.collapse(true);
        sel.removeAllRanges();
        sel.addRange(after);
        return true;
    }
    return false;
}
/* is the caret touching a struck run (inside it, or right after it)? */
function ovAtCaret(root, r) {
    if (ovAncestor(r.startContainer, root)) return true;
    const c = r.startContainer;
    let prev = null;
    if (c.nodeType === 3) prev = r.startOffset === 0 ? c.previousSibling : null;
    else prev = c.childNodes[r.startOffset - 1] ?? null;
    return prev instanceof HTMLElement && prev.classList.contains('ov');
}
function insertPlain(root, text) {
    const sel = window.getSelection();
    if (!sel || !sel.rangeCount) return;
    const r = sel.getRangeAt(0);
    const node = document.createTextNode(text);
    r.insertNode(node);
    const after = document.createRange();
    after.setStart(node, node.data.length);
    after.collapse(true);
    sel.removeAllRanges();
    sel.addRange(after);
    root.normalize();
}
/* Enter makes a real paragraph (its own block, indented like the archive's), Shift+Enter a soft line */
function splitParagraph(root) {
    const sel = window.getSelection();
    if (!sel || !sel.rangeCount) return;
    const r = sel.getRangeAt(0);
    let block = r.startContainer;
    while (block && block.parentNode !== root) block = block.parentNode;
    const np = document.createElement('p');
    if (
        !block ||
        block === root ||
        !(block instanceof HTMLElement) ||
        !BLOCK.test(block.nodeName)
    ) {
        // loose text at the root: wrap everything up to the caret into its own paragraph first
        const head = document.createElement('p');
        const pre = document.createRange();
        pre.setStart(root, 0);
        pre.setEnd(r.startContainer, r.startOffset);
        head.appendChild(pre.extractContents());
        const tail = document.createRange();
        tail.selectNodeContents(root);
        np.appendChild(tail.extractContents());
        root.appendChild(head);
        root.appendChild(np);
    } else {
        const tail = document.createRange();
        tail.setStart(r.startContainer, r.startOffset);
        tail.setEnd(block, block.childNodes.length);
        np.appendChild(tail.extractContents());
        block.after(np);
        block.querySelectorAll('s.ov').forEach((e) => {
            if (!e.textContent) e.remove();
        });
        if (!block.textContent) block.innerHTML = '<br>';
    }
    np.querySelectorAll('s.ov').forEach((e) => {
        if (!e.textContent) e.remove();
    });
    if (!np.textContent) np.innerHTML = '<br>';
    // a trailing newline left at the split point would render nothing but survive as a stray break
    const c = document.createRange();
    c.setStart(np, 0);
    c.collapse(true);
    sel.removeAllRanges();
    sel.addRange(c);
}

/* ---- editor input pipeline -----------------------------------------------
 * Intercepts beforeinput/keydown on draft bodies: Enter makes a real paragraph,
 * formatting shortcuts, and commitment-mode deletes.
 */
function attachCommit(el, pref) {
    if (!el || el.__wtCommit) return;
    el.__wtCommit = true;
    const fire = () => el.dispatchEvent(new Event('input', { bubbles: true }));
    // Enter = new paragraph block; Shift+Enter stays a soft line inside the paragraph
    el.addEventListener('keydown', (e) => {
        if ((e.metaKey || e.ctrlKey) && !e.altKey && el.classList.contains('story-text')) {
            const k = e.key.toLowerCase();
            const tag =
                k === 'i'
                    ? 'EM'
                    : k === 'b'
                      ? 'STRONG'
                      : k === 'u'
                        ? 'U'
                        : k === 'x' && e.shiftKey
                          ? 'DEL'
                          : '';
            if (tag) {
                e.preventDefault();
                toggleFx(el, tag);
                return;
            }
        }
        if (e.key !== 'Enter' || e.shiftKey || e.isComposing || e.metaKey || e.ctrlKey || e.altKey)
            return;
        e.preventDefault();
        const sel = window.getSelection();
        if (!sel || !sel.rangeCount) return;
        const range = sel.getRangeAt(0);
        if (!range.collapsed) {
            if (pref.current.commit) strikeRange(el, range);
            else range.deleteContents();
            const end = document.createRange();
            end.setStart(range.endContainer, range.endOffset);
            sel.removeAllRanges();
            sel.addRange(end);
            caretOutsideOv(el);
        }
        splitParagraph(el);
        fire();
    });
    el.addEventListener('beforeinput', (ev) => {
        const e = ev;
        const sel = window.getSelection();
        if (!sel || !sel.rangeCount) return;
        const range = sel.getRangeAt(0);
        const t = e.inputType;
        if (t === 'insertParagraph') {
            e.preventDefault();
            if (!range.collapsed) {
                if (pref.current.commit) strikeRange(el, range);
                else range.deleteContents();
                const end = document.createRange();
                end.setStart(range.endContainer, range.endOffset);
                sel.removeAllRanges();
                sel.addRange(end);
                caretOutsideOv(el);
            }
            splitParagraph(el);
            fire();
            return;
        }
        if (!pref.current.commit) {
            if (t === 'insertText' && e.data && range.collapsed && ovAtCaret(el, range)) {
                e.preventDefault();
                caretOutsideOv(el);
                insertPlain(el, e.data);
                fire();
            }
            return;
        }
        if (t.startsWith('delete')) {
            e.preventDefault();
            if (!range.collapsed) {
                strikeRange(el, range);
                const end = document.createRange();
                end.setStart(range.endContainer, range.endOffset);
                sel.removeAllRanges();
                sel.addRange(end);
            } else {
                // a comment marks the carriage so splitting text around it can't move the caret
                const mark = document.createComment('c');
                range.insertNode(mark);
                const at = document.createRange();
                at.setStartAfter(mark);
                at.collapse(true);
                if (
                    t === 'deleteContentBackward' ||
                    t === 'deleteWordBackward' ||
                    t === 'deleteSoftLineBackward' ||
                    t === 'deleteHardLineBackward'
                ) {
                    strikeBack(el, at, t !== 'deleteContentBackward', false);
                } else {
                    strikeBack(el, at, t !== 'deleteContentForward', true);
                }
                const back = document.createRange();
                if (mark.parentNode) {
                    back.setStartBefore(mark);
                    back.collapse(true);
                }
                mark.remove();
                sel.removeAllRanges();
                sel.addRange(back);
            }
            // keep the carriage outside the strike it just made
            caretOutsideOv(el);
            fire();
            return;
        }
        if (
            t === 'insertText' ||
            t === 'insertReplacementText' ||
            t === 'insertFromPaste' ||
            t === 'insertLineBreak'
        ) {
            // typing over a selection strikes it first, then writes after it
            if (!range.collapsed) {
                strikeRange(el, range);
                const end = document.createRange();
                end.setStart(range.endContainer, range.endOffset);
                sel.removeAllRanges();
                sel.addRange(end);
                caretOutsideOv(el);
                if (t === 'insertText' && e.data) {
                    e.preventDefault();
                    insertPlain(el, e.data);
                    fire();
                }
                return;
            }
            if (ovAtCaret(el, range) && t === 'insertText' && e.data) {
                e.preventDefault();
                caretOutsideOv(el);
                insertPlain(el, e.data);
                fire();
            }
        }
    });
}
/* ---- commitText: one editor-owned way to write text at the caret (dictation write-back) ----
   Runs the editor's own guards (strike-instead-of-replace, never write inside a struck run) and writes
   through execCommand so one browser undo removes the whole text. At a struck run's boundary
   execCommand would put the text inside the strike (measured), so that case uses plain DOM insertion:
   undoable:false. Never touches the title; ok:false writes nothing. */
function commitText(el, text, { commit = false, range = null, atomic = false } = {}) {
    if (!el || typeof text !== 'string' || !text) return { ok: false, inserted: 0, reason: 'empty' };
    const sel = window.getSelection();
    if (!sel) return { ok: false, inserted: 0, reason: 'no-selection' };
    if (range) {
        if (!range.startContainer.isConnected || !el.contains(range.startContainer) || !el.contains(range.endContainer))
            return { ok: false, inserted: 0, reason: 'range-detached' };
        sel.removeAllRanges();
        sel.addRange(range);
    } else if (!sel.rangeCount || !el.contains(sel.getRangeAt(0).startContainer)) {
        return { ok: false, inserted: 0, reason: 'no-caret' };
    }
    const r = sel.getRangeAt(0);
    // Dictation's owned range uses one native replacement command, never a DOM delete or fallback.
    // Fail closed at struck runs, including a struck boundary, before changing any content.
    if (atomic) {
        if (commit) return { ok: false, inserted: 0, reason: 'atomic-commit-unsupported' };
        const start = r.cloneRange(); start.collapse(true);
        const end = r.cloneRange(); end.collapse(false);
        if (ovAtCaret(el, start) || ovAtCaret(el, end) ||
            [...el.querySelectorAll('s.ov')].some(n => r.intersectsNode(n)))
            return { ok: false, inserted: 0, reason: 'atomic-struck-range' };
        const ok = document.execCommand('insertText', false, text.replace(/\r\n?/g, '\n'));
        return { ok, inserted: ok ? text.length : 0, undoable: ok,
            ...(ok ? {} : { reason: 'atomic-native-rejected' }) };
    }
    if (!r.collapsed) {
        if (commit) strikeRange(el, r);
        else r.deleteContents();
        const end = document.createRange();
        end.setStart(r.endContainer, r.endOffset);
        end.collapse(true);
        sel.removeAllRanges();
        sel.addRange(end);
    }
    const parts = text.replace(/\r\n?/g, '\n').split('\n');
    const atStrike = ovAtCaret(el, sel.getRangeAt(0));
    let undoable = !atStrike;
    if (atStrike) caretOutsideOv(el);
    const plain = (s) => { if (s) insertPlain(el, s); };
    let ok = true;
    parts.forEach((part, i) => {
        if (i > 0) {
            if (undoable && document.execCommand('insertParagraph')) { /* native split */ }
            else { splitParagraph(el); undoable = false; }
        }
        if (!part) return;
        if (undoable && document.execCommand('insertText', false, part)) return;
        plain(part);
        undoable = false;
    });
    if (!undoable) el.dispatchEvent(new Event('input', { bubbles: true }));
    return { ok, inserted: text.length, undoable };
}
/* ---- Tab in a piece ----
   Tab at a caret writes a tab character. It goes through the normal typing path (insertText), so
   draft mode's strike-instead-of-delete rules apply to it as to any letter.
   Tab over a selection indents every paragraph the selection touches (a tab at each start);
   Shift+Tab takes one leading tab off each of them, or off the caret's own paragraph.
   The selection stays where it was, so Tab can be pressed again to go deeper. */
function tabKey(root, back) {
    const sel = window.getSelection();
    if (!sel || !sel.rangeCount) return;
    const range = sel.getRangeAt(0);
    if (!back && range.collapsed) {
        if (!document.execCommand('insertText', false, '\t')) insertPlain(root, '\t');
        return;
    }
    const paras = [...root.children].filter((p) => range.intersectsNode(p));
    if (!paras.length) return;
    let changed = false;
    for (const p of paras) {
        // where the paragraph's text begins: its first character that isn't a line break,
        // wherever it sits (it may be inside a struck or styled span)
        const walk = document.createTreeWalker(p, NodeFilter.SHOW_TEXT);
        let at = null;
        for (let n = walk.nextNode(); n && !at; n = walk.nextNode()) {
            const i = n.data.search(/[^\n]/);
            if (i >= 0) at = { t: n, i };
        }
        if (!back) {
            if (at) at.t.insertData(at.i, '\t');
            else p.appendChild(document.createTextNode('\t'));
            changed = true;
        } else if (at && at.t.data[at.i] === '\t') {
            at.t.deleteData(at.i, 1);
            changed = true;
        }
    }
    // the page saves on input events; this edit bypassed typing, so announce it
    if (changed) root.dispatchEvent(new Event('input', { bubbles: true }));
}
/* contentEditable regions capture their seed once per version identity so React
   re-renders never reconcile against browser-mutated DOM (which duplicates text) */

/* ---- draft-mode piece ----------------------------------------------------
 * Editable title/body seeded once per version, so React never reconciles
 * against DOM the browser is editing. WorkStory adds the version stack.
 */
/* plus -> cross morph variations: never the same one twice running */
/* the plus (and its html.plus-wipe state) is one shared element: only the piece that owns it may tear its morph down,
   and any piece whose wipe is live takes it over, so a timer from a piece the pointer already left cannot kill it */
let plusOwner = null;
let plusOutTimer = 0;
let lastMorph = -1;
function pickMorph() {
    let n;
    do { n = Math.floor(randomUnit() * 64); } while (n === lastMorph);
    lastMorph = n;
    const bit = (k) => (n >> k) & 1;
    // the horizontal stroke lands on one diagonal and the vertical on the other, each turning cw or ccw
    const a = bit(0) ? (bit(1) ? 135 : -45) : (bit(1) ? 45 : -135);
    const bRot = bit(0) ? (bit(2) ? 135 : -45) : (bit(2) ? 45 : -135);
    const eases = ['ease-in-out', 'cubic-bezier(.5,-.4,.3,1.4)', 'cubic-bezier(.2,.8,.2,1)', 'cubic-bezier(.7,0,.3,1)'];
    const r = () => randomUnit();
    const tones = bit(3) ? ['var(--dim)', 'var(--ink)'] : ['var(--ink)', 'var(--dim)'];
    return {
        '--m-a': `${a}deg`, '--m-b': `${bRot}deg`,
        '--m-ad': `${Math.round(r() * 140)}ms`, '--m-bd': `${Math.round(r() * 200)}ms`,
        '--m-at': `${Math.round(220 + r() * 260)}ms`, '--m-bt': `${Math.round(260 + r() * 300)}ms`,
        '--m-ease': eases[(n >> 4) & 3], '--m-from-a': tones[0], '--m-from-b': tones[1],
    };
}
function EditableTitle({ id, title, register, onInput }) {
    const [initial] = reactExports.useState(title);
    return jsxRuntimeExports.jsx('span', {
        className: 'story-title editable',
        contentEditable: 'plaintext-only',
        suppressContentEditableWarning: true,
        spellCheck: false,
        'data-ph': 'title',
        ref: (el) => register(id, 'title', el),
        onInput: onInput,
        children: initial,
    });
}
function EditableBody({ id, lines, audio = [], register, onInput }) {
    const [initial] = reactExports.useState(lines);
    return jsxRuntimeExports.jsx('div', {
        className: 'story-text editable',
        contentEditable: 'plaintext-only',
        suppressContentEditableWarning: true,
        spellCheck: false,
        ref: (el) => register(id, 'text', el),
        onInput: onInput,
        onKeyDown: (e) => {
            if (e.key !== 'Tab' || e.altKey || e.ctrlKey || e.metaKey || e.nativeEvent.isComposing)
                return;
            e.preventDefault();
            tabKey(e.currentTarget, e.shiftKey);
        },
        children: (initial.length ? initial : ['']).map((line, i) => jsxRuntimeExports.jsxs(reactExports.Fragment, {
            children: [jsxRuntimeExports.jsx('p', { children: line ? jsxRuntimeExports.jsx(ParaText, { text: line }) : null }),
                ...audioAt(audio, i + 1, initial.length).map(a => jsxRuntimeExports.jsx('div', {
                    className: 'story-audio', 'data-audio-part': '', contentEditable: false,
                    children: jsxRuntimeExports.jsx(AudioPart, { id: id + '-' + a.index, src: a.src, label: a.label })
                }, 'audio-' + a.index))]
        }, i)),
    });
}
/* Collect snapshots from every version, newest first. Equal timestamps are not deduplicated:
   two versions can have different past selves captured at the same time. No data is rewritten. */
function pieceSnapshots(wp) {
    return (wp.versions ?? []).flatMap(v => v.snaps ?? []).sort((a, b) => (b.t ?? 0) - (a.t ?? 0));
}

/* One date row. While the list closes, its letters are removed from the right end, row by row, the
   opening's typewriter run backwards; the last row to finish drops the list. */
function HistoryDate({ sn, i, serial, on, closing, last, onPick, onGone }) {
    const full = sn.at;
    const [n, setN] = reactExports.useState(full.length);
    reactExports.useEffect(() => {
        if (!closing) { setN(full.length); return undefined; }
        const calm = matchMedia('(prefers-reduced-motion: reduce)').matches;
        if (calm) { if (last) onGone(); return undefined; }
        let t = 0, k = full.length;
        const tick = () => {
            k -= 1;
            setN(Math.max(0, k));
            if (k > 0) t = setTimeout(tick, 28);
            else if (last) onGone();
        };
        t = setTimeout(tick, i * 60);
        return () => clearTimeout(t);
    }, [closing]);
    return jsxRuntimeExports.jsx('button', {
        type: 'button',
        className: `history-date${on ? ' on' : ''}${closing ? ' erasing' : ''}`,
        style: { '--i': i },
        onClick: onPick,
        children: [
            /* the serial stands on the text area's left edge (--serial-x, measured by the list), flowing right,
               dimmer than the date; while the row erases it loses its letters in step with the date */
            jsxRuntimeExports.jsx('span', {
                className: 'history-serial',
                'aria-hidden': 'true',
                children: closing ? serial.slice(0, Math.ceil((serial.length * n) / Math.max(1, full.length))) : serial,
            }, 'serial'),
            closing ? full.slice(0, n) || '\u00A0' : full,
        ],
    });
}
/* typing-focus plus (ruling 23:18, patch 2): while the draft is actively typed in, the add plus hides
   (opacity/visibility only, zero layout shift - see chrome.css) and reappears ~2s after the last keystroke.
   Focus alone never hides it (this runs on input, not focus). It never hides while the history list or a
   menu from it is open (patch 1's hist-open pin), nor while the plus is the wipe's delete button.
   Touch types through the same input events. */
const TYPING_HIDE_MS = 2000;
let typingHideTimer = 0;
const typingPing = () => {
    const root = document.documentElement;
    if (root.classList.contains('hist-open') || root.classList.contains('plus-wipe')) {
        clearTimeout(typingHideTimer);
        root.classList.remove('plus-typing');
        return;
    }
    root.classList.add('plus-typing');
    clearTimeout(typingHideTimer);
    typingHideTimer = setTimeout(() => root.classList.remove('plus-typing'), TYPING_HIDE_MS);
};
function HistoryEnd({ snaps, open, peek, setPeek, onRestore }) {
    // history lives at the end of the text: hovering the blinking middots stops the blink and types the
    // word "history" beside them on the same row; clicking that typed title pins it as a button, with its
    // caret still blinking. The button opens the dates below it, line by line. idle -> hover -> pinned.
    const [hMode, setHMode] = reactExports.useState('idle');
    const [drop, setDrop] = reactExports.useState(false);
    const [closing, setClosing] = reactExports.useState(false);
    const closeTimer = reactExports.useRef(0);
    const inside = reactExports.useRef(false);
    const hostRef = reactExports.useRef(null);
    const stopRef = reactExports.useRef(null);
    const pinRef = reactExports.useRef(null);
    const mouse = (e) => e.pointerType === 'mouse';
    const hasHistory = snaps.length > 0;
    const hoverIn = () => {
        if (hMode !== 'idle' || !hostRef.current) return;
        setHMode('hover');
        stopRef.current = typeInto(hostRef.current, 'history', { dir: 'ltr-right' });
    };
    const hoverOut = () => {
        if (hMode !== 'hover') return;
        stopRef.current?.();
        stopRef.current = null;
        setHMode('idle');
    };
    const pinIn = () => {
        // Keep an in-progress typewriter and its live caret when the title is pinned.
        if (!hostRef.current?.textContent) stopRef.current = typeInto(hostRef.current, 'history', { dir: 'ltr-right' });
        setHMode('pinned');
    };
    const openDrop = () => {
        clearTimeout(closeTimer.current);
        setClosing(false);
        setDrop(true);
    };
    const dropped = () => {
        clearTimeout(closeTimer.current);
        setClosing(false);
        setDrop(false);
    };
    const unpin = () => {
        stopRef.current?.dispose?.();
        stopRef.current = null;
        hostRef.current?.replaceChildren();
        dropped();
        setPeek(null);
        setHMode('idle');
    };
    reactExports.useEffect(() => () => { stopRef.current?.dispose?.(); clearTimeout(closeTimer.current); }, []);
    /* ruling 23:18 (patch 1): the close-set is exhaustive - outside click, Esc, or the opening toggle.
       The idle auto-close (typed-back-out after a pause) is NOT among them and used to erase the list
       mid multi-delete, so it no longer arms. FLAGGED to the architect: this retires the idle type-out. */
    reactExports.useEffect(() => {
        if (!drop) return undefined;
        const away = (e) => {
            /* ruling 23:18 (patch 1): the list closes ONLY on a click outside both the list and the wipe plus -
               the plus is the delete button of the selected row, and the list's own controls are inside the list */
            if (!pinRef.current?.contains(e.target) && !e.target?.closest?.('.hair-plus') && !e.target?.closest?.('.history-list, .history-actions')) dropped();
        };
        const esc = (e) => { if (e.key === 'Escape') dropped(); }; // ruling 23:18: Esc is one of the three exits
        document.addEventListener('pointerdown', away);
        document.addEventListener('keydown', esc);
        return () => { document.removeEventListener('pointerdown', away); document.removeEventListener('keydown', esc); };
    }, [drop]);
    reactExports.useEffect(() => {
        /* ruling 23:18 (patch 1 pins the plus visible): while the history list or a menu from it is open,
           patch 2's typing hide stays off */
        const root = document.documentElement;
        const on = drop || !!peek;
        root.classList.toggle('hist-open', on);
        if (on) root.classList.remove('plus-typing');
        return () => root.classList.remove('hist-open');
    }, [drop, peek]);
    reactExports.useEffect(() => {
        /* ruling 23:18 (patch 1): deleting the last entry leaves the EMPTY list open - only the piece
           itself closing tears the list down, never the count hitting zero mid-session */
        if (!open) {
            setHMode('idle');
            dropped();
        }
    }, [hasHistory, open]);
    return jsxRuntimeExports.jsxs('div', {
        className: `hist-end ${hMode}${drop ? ' drop' : ''}`,
        onPointerLeave: (e) => {
            if (mouse(e)) hoverOut();
        },
        children: [
            jsxRuntimeExports.jsx('button', {
                type: 'button',
                className: 'endmark hist-mark',
                'aria-label': hMode === 'pinned' ? 'close history' : 'history',
                'aria-expanded': hMode === 'pinned',
                onPointerEnter: (e) => {
                    if (mouse(e)) hoverIn();
                },
                onFocus: (e) => {
                    if (e.currentTarget.matches(':focus-visible')) hoverIn();
                },
                onBlur: hoverOut,
                onClick: () => (hMode === 'pinned' ? unpin() : pinIn()),
                children: '\u00B7 \u00B7',
            }),
            jsxRuntimeExports.jsxs('span', {
                className: 'hist-pin',
                ref: pinRef,
                onPointerEnter: (e) => {
                    if (mouse(e)) {
                        inside.current = true;
                        if (hMode === 'idle') hoverIn();
                        else if (hMode === 'pinned') openDrop();
                    }
                },
                onPointerLeave: (e) => {
                    if (mouse(e)) {
                        inside.current = false;
                        if (hMode === 'hover') hoverOut();
                        /* ruling 23:18 (patch 1): pointer leaving no longer arms the idle close */
                    }
                },
                children: [
                    jsxRuntimeExports.jsx('button', {
                        type: 'button',
                        className: 'hist-type',
                        onPointerEnter: (e) => {
                            // the typed title itself opens the list: no click needed
                            if (mouse(e) && hMode === 'hover') {
                                inside.current = true;
                                pinIn();
                                openDrop();
                            }
                        },
                        ref: hostRef,
                        'aria-hidden': hMode !== 'pinned',
                        'aria-label': hMode === 'pinned' ? `history, ${snaps.length} versions` : 'history',
                        'aria-expanded': hMode === 'pinned' && drop,
                        onFocus: (e) => {
                            if (e.currentTarget.matches(':focus-visible')) {
                                if (hMode === 'idle') hoverIn();
                                else if (hMode === 'pinned') openDrop();
                            }
                        },
                        onBlur: () => { if (hMode === 'hover') hoverOut(); },
                        onClick: () => (hMode === 'pinned' ? (drop ? dropped() : openDrop()) : (pinIn(), openDrop())),
                    }),
                    hMode === 'pinned' &&
                        jsxRuntimeExports.jsx('span', {
                            className: 'history-count',
                            children: snaps.length,
                        }),
                    peek &&
                        jsxRuntimeExports.jsxs('span', {
                            className: 'history-actions',
                            children: [
                                jsxRuntimeExports.jsx('button', {
                                    type: 'button',
                                    className: 'history-act',
                                    onClick: () => setPeek(null),
                                    children: 'back',
                                }),
                                jsxRuntimeExports.jsx('button', {
                                    type: 'button',
                                    className: 'history-act strong',
                                    onClick: () => {
                                        onRestore(peek);
                                        setPeek(null);
                                        dropped();
                                    },
                                    children: 'restore as new draft',
                                }),
                            ],
                        }),
                    drop &&
                        jsxRuntimeExports.jsx('span', {
                            className: 'history-list',
                            ref: (el) => {
                                const end = el?.closest('.hist-end');
                                if (end) el.style.setProperty('--serial-x', end.getBoundingClientRect().left - el.getBoundingClientRect().left + 'px');
                            },
                            children: snaps.map((sn, i) =>
                                jsxRuntimeExports.jsx(
                                    HistoryDate,
                                    {
                                        sn,
                                        i,
                                        /* oldest = 001, so a number keeps naming its snapshot as history grows */
                                        serial: String(snaps.length - i).padStart(3, '0'),
                                        on: peek === sn,
                                        closing,
                                        last: i === snaps.length - 1,
                                        onPick: () => setPeek(peek === sn ? null : sn),
                                        onGone: dropped,
                                    },
                                    i,
                                ),
                            ),
                        }),
                ],
            }),
        ],
});
}

/* NQK4EKT4: date, time and offset as designed cells; a non-stamp falls back to the plain text */
const whenCellNodes = (w) => {
    const cells = whenCells(w);
    if (!cells) return [whenSealed(w)];
    return cells.flatMap(([cls, text], i) =>
        i
            ? [' ', jsxRuntimeExports.jsx('span', { className: cls, children: text }, cls)]
            : [jsxRuntimeExports.jsx('span', { className: cls, children: text }, cls)],
    );
};

function WorkStory({
    wp,
    num,
    resting,
    onActive,
    open,
    onToggle,
    register,
    onEditInput,
    onLoadVersion,
    onDuplicate,
    onRemoveVersion,
    onRemoveSnap,
    onRemove,
    onRestore,
    onToggleEndmark,
    measure,
    onMeasure,
    layoutStyle,
    layout,
    shared = false,
    onShareToggle = null,
    onSharePress = null,
    onShareHover = null,
    shareNotice = null,
    onShareNoticeDone = null,
    onShareNoticeCopied = null,
}) {
    const v = wp.versions[wp.current];
    const [hoverV, setHoverV] = reactExports.useState(null);
    // past selves: the list folds out under the text; peeking shows one in place of the editor
    // (the editor stays mounted underneath, so its caret and DOM survive the peek)
    const [peek, setPeek] = reactExports.useState(null);
    const snaps = pieceSnapshots(wp);
    const hasHistory = snaps.length > 0;
    /* ruling 23:18 (patch 1): a list emptied by deletes stays open - once this piece had history in
       this seat, HistoryEnd keeps rendering so the wipe's last row never unmounts the list mid-session */
    const hadHistory = reactExports.useRef(false);
    if (hasHistory) hadHistory.current = true;
    reactExports.useEffect(() => {
        setPeek(null);
    }, [wp.seat]);
    /* one wipe for every delete: it sits on the plus's vertical axis and follows the hovered row of
       this piece (the title's first line, or a version row), always level with the active row */
    const headRef = reactExports.useRef(null);
    /* NQK4EKT4: stack the head's cells when the title line or the when row no longer fits */
    useStackedHead(headRef);
    /* a long press on the piece's middot shares or unshares it (the bullet) - the same
       550ms hold the reading page uses; a held press is not a click, so it never folds */
    const shareHold = reactExports.useRef(undefined);
    const shareHeld = reactExports.useRef(false);
    const shareClip = reactExports.useRef(null);
    const sharePress = () => {
        if (!onShareToggle) return;
        shareHeld.current = false;
        window.clearTimeout(shareHold.current);
        shareClip.current?.reject();
        shareClip.current = onSharePress?.() ?? null;
        shareHold.current = window.setTimeout(() => {
            shareHeld.current = true;
            const clip = shareClip.current;
            shareClip.current = null;
            onShareToggle(clip);
        }, 550);
    };
    const shareRelease = () => {
        window.clearTimeout(shareHold.current);
        if (!shareHeld.current) { shareClip.current?.reject(); shareClip.current = null; }
    };
    reactExports.useEffect(() => () => { window.clearTimeout(shareHold.current); shareClip.current?.reject(); }, []);
    /* the fresh link announces itself once at the bullet, typed by the house typer and taken
       back; hovering the red bullet re-tells it through data-tip */
    /* clipboard truth at the middot: 'link copied' types only after a real clipboard
       success; when both clipboard paths fail, 'link ready, copy it' stays with the link
       itself in one inline field - copying out of it earns the copied notice, Escape or
       leaving the field dismisses */
    const shareTipRef = reactExports.useRef(null);
    const shareFieldRef = reactExports.useRef(null);
    reactExports.useEffect(() => {
        if (!shareNotice || !shareTipRef.current) return undefined;
        const ready = shareNotice.kind === 'ready';
        const stop = typeInto(shareTipRef.current, ready ? 'link ready, copy it' : 'link copied', { dir: 'ltr-right' });
        if (ready) {
            shareFieldRef.current?.focus();
            shareFieldRef.current?.select();
            return () => { stop.dispose(); shareTipRef.current?.querySelectorAll('.tip-caret').forEach((c) => c.remove()); };
        }
        const t = window.setTimeout(() => { stop(); onShareNoticeDone?.(); }, 2000);
        return () => { window.clearTimeout(t); stop.dispose(); shareTipRef.current?.querySelectorAll('.tip-caret').forEach((c) => c.remove()); };
    }, [shareNotice]);
    const hideWipe = reactExports.useRef(0);
    const [wipe, setWipe] = reactExports.useState(null);
    // a version the reader picked keeps the wipe parked on its row; hovering moves it, leaving brings it back
    const [picked, setPicked] = reactExports.useState(false);
    const parked = () => {
        if (!picked || wp.versions.length < 2 || document.documentElement.classList.contains('idx-out')) return null;
        const y = rowY('version', wp.current);
        return y == null ? null : { kind: 'version', i: wp.current, y };
    };
    const sectionRef = reactExports.useRef(null);
    const snapsRef = reactExports.useRef(snaps);
    snapsRef.current = snaps;
    const rowY = (kind, i) => {
        if (kind === 'snap') {
            const row = sectionRef.current?.querySelectorAll('.history-date')[i];
            if (!row) return null;
            const b = row.getBoundingClientRect();
            return b.top + b.height / 2;
        }
        const head = headRef.current;
        if (!head) return null;
        if (kind === 'version') {
            const row = head.querySelectorAll('.vrow:not(.add) .vrow-inner')[i];
            if (!row) return null;
            const b = row.getBoundingClientRect();
            return b.top + b.height / 2;
        }
        const t = head.querySelector('.story-title.editable');
        if (!t) return null;
        const fs = parseFloat(getComputedStyle(t).fontSize) || 14;
        const lh = parseFloat(getComputedStyle(t).lineHeight) || fs * 1.42;
        return t.getBoundingClientRect().top + lh / 2;
    };
    // a hidden index (html.idx-out) has no rows to act on: its boxes are still in place, but nothing may wake the wipe
    const idxHidden = () => document.documentElement.classList.contains('idx-out');
    const aim = (e) => {
        clearTimeout(hideWipe.current);
        const head = headRef.current;
        if (!head || idxHidden()) return;
        const rows = [...head.querySelectorAll('.vrow:not(.add) .vrow-inner')];
        // the wipe is called only by the row's own text: a version row from its serial to the end of its date,
        // the title row from the serial's x to the end of the title (the date's end when the piece has no title)
        const textRight = (el) => { if (!el) return null; const rg = document.createRange(); rg.selectNodeContents(el); const rc = rg.getBoundingClientRect(); return rc.width ? rc.right : null; };
        const dateRight = (r) => textRight(r?.querySelector('.story-when'));
        const hit = rows.findIndex((r) => {
            const b = r.getBoundingClientRect();
            const right = dateRight(r) ?? b.right;
            return e.clientY >= b.top && e.clientY <= b.bottom && e.clientX >= b.left && e.clientX <= right;
        });
        // only the title or a version row calls the wipe; gaps and the add row leave it where it is, so
        // crossing them on the way to the button at the screen's edge never steals it
        const titleEl = head.querySelector('.story-title.editable');
        const tb = titleEl?.getBoundingClientRect();
        const dotEl = head.querySelector('.fold-dot');
        const serialLeft = dotEl?.getBoundingClientRect().left ?? rows[0]?.getBoundingClientRect().left ?? tb?.left;
        const titleText = titleEl && (titleEl.textContent || '').trim() ? textRight(titleEl) : null;
        const titleRight = titleText ?? dateRight(rows[0]) ?? (tb ? tb.left + 1 : null);
        const onTitle = !!tb && e.clientY >= tb.top && e.clientY <= tb.bottom && titleRight != null && e.clientX >= serialLeft && e.clientX <= titleRight;
        // an original is never deleted as a version: its date row arms nothing (the title row still arms the piece)
        const hitOriginal = hit >= 0 && wp.versions.length > 1 && !!wp.versions[hit]?.original;
        if ((hit < 0 || hitOriginal) && !onTitle) { clearTimeout(hideWipe.current); return; }
        const row = hitOriginal ? -1 : hit;
        const kind = row >= 0 ? 'version' : 'piece';
        const y = rowY(kind, row);
        reclaim();
        if (y != null) setWipe((w) => (w && w.kind === kind && w.i === row && Math.abs(w.y - y) < 0.5
            ? w
            : { kind, i: row, y, seed: w?.seed ?? Array.from({ length: 4 }, () => randomUnit()) }));
    };
    /* the history list (past selves) lives below the text, outside the head: its dates take the same wipe */
    const aimSnap = (e) => {
        // a row's own text runs unbroken from its serial through the end of its date (the serial is absolutely placed,
        // so the gap between them is outside the button): decide by position, not by what is under the pointer
        let row = e.target.closest?.('.history-date');
        const sec = sectionRef.current;
        const near = (r) => { const b = r.getBoundingClientRect(); const rg = document.createRange(); rg.selectNodeContents(r); const rc = rg.getBoundingClientRect(); return { b, rc }; };
        if (e.clientX != null && e.clientY != null && sec) {
            row = [...sec.querySelectorAll('.history-date')].find((r) => {
                const { b, rc } = near(r);
                return rc.width && e.clientY >= b.top && e.clientY <= b.bottom && e.clientX >= rc.left && e.clientX <= rc.right;
            }) ?? null;
        } else if (row) {
            const { rc } = near(row);
            if (rc.width && (e.clientX < rc.left || e.clientX > rc.right)) row = null;
        }
        const section = sectionRef.current;
        if (!row || !section) {
            // the pointer resting on the wipe button itself is not leaving it
            if (wipeRef.current?.kind === 'snap' && !e.target?.closest?.('.hair-plus')) letGoWipe();
            return;
        }
        clearTimeout(hideWipe.current);
        const i = [...section.querySelectorAll('.history-date')].indexOf(row);
        const y = rowY('snap', i);
        reclaim();
        if (i >= 0 && y != null) setWipe((w) => (w && w.kind === 'snap' && w.i === i && Math.abs(w.y - y) < 0.5
            ? w
            : { kind: 'snap', i, y, seed: w?.seed ?? Array.from({ length: 4 }, () => randomUnit()) }));
    };
    reactExports.useEffect(() => {
        const section = sectionRef.current;
        if (!section) return undefined;
        // leaving the piece (or the window) lets a history entry's wipe go, like the head's own pointerleave
        const leave = (e) => { if (e?.pointerType === 'touch') return; if (wipeRef.current?.kind === 'snap') letGoWipe(); }; // a finger lifting is not a pointer leaving: on touch the wipe stays until a press outside
        // tracked on the document: the serial is placed left of the section's own box (on a phone that stretch
        // belongs to the page, not the section), and the row's hit area is decided by position, not by target
        document.addEventListener('pointermove', aimSnap, true);
        document.addEventListener('pointerdown', aimSnap, true);
        section.addEventListener('pointerleave', leave);
        return () => {
            document.removeEventListener('pointermove', aimSnap, true);
            document.removeEventListener('pointerdown', aimSnap, true);
            section.removeEventListener('pointerleave', leave);
        };
    });
    // where the pointer last was: a scroll moves the rows under a still pointer, so the wipe re-aims there
    const lastPtr = reactExports.useRef(null);
    reactExports.useEffect(() => {
        const note = (e) => { lastPtr.current = { x: e.clientX, y: e.clientY }; };
        document.addEventListener('pointermove', note, true);
        document.addEventListener('pointerdown', note, true);
        return () => {
            document.removeEventListener('pointermove', note, true);
            document.removeEventListener('pointerdown', note, true);
        };
    }, []);
    const letGoWipe = () => {
        clearTimeout(hideWipe.current);
        // long enough to cross from the row to the button at the screen's edge
        hideWipe.current = setTimeout(() => setWipe((w) => { const k = parked(); return k ? { ...k, seed: w?.seed ?? Array.from({ length: 4 }, () => randomUnit()) } : null; }), 900);
    };
    // hiding the index drops a wipe that sits on one of its rows (a history entry's wipe is not the index's)
    reactExports.useEffect(() => {
        const root = document.documentElement;
        const watch = new MutationObserver(() => {
            if (root.classList.contains('idx-out')) setWipe((w) => (w && w.kind !== 'snap' ? null : w));
        });
        watch.observe(root, { attributes: true, attributeFilter: ['class'] });
        return () => watch.disconnect();
    }, []);
    reactExports.useEffect(() => {
        const park = () => setWipe((w) => {
            const k = parked();
            if (!k) return wp.versions.length < 2 && w?.kind === 'version' ? null : w;
            return { ...k, seed: w?.seed ?? Array.from({ length: 4 }, () => randomUnit()) };
        });
        park();
        const later = setTimeout(park, 650); // the version stack unfolds over 0.55s
        return () => clearTimeout(later);
    }, [picked, wp.current, wp.versions.length, wp.seat, open]);
    reactExports.useEffect(() => {
        if (!wipe) return;
        const follow = () => {
            const w0 = wipeRef.current;
            const p = lastPtr.current;
            if (w0 && p) {
                const under = document.elementFromPoint(p.x, p.y);
                if (w0.kind === 'snap') {
                    const row = under?.closest?.('.history-date');
                    if (row && sectionRef.current?.contains(row)) { aimSnap({ target: row, clientX: p.x, clientY: p.y }); return; }
                } else if (under && headRef.current?.contains(under)) {
                    aim({ clientX: p.x, clientY: p.y });
                    return;
                }
            }
            setWipe((w) => {
                if (!w) return w;
                const y = rowY(w.kind, w.i);
                if (y == null) return w;
                // a history entry scrolled out of sight takes its wipe with it
                if (w.kind === 'snap' && (y < 0 || y > window.innerHeight)) return null;
                return Math.abs(y - w.y) < 0.5 ? w : { ...w, y };
            });
        };
        const away = (e) => { if (e.pointerType === 'touch' && !e.target.closest?.('.wipe, .history-date, .hair-plus') && !headRef.current?.contains(e.target)) letGoWipe(); }; // a press on a history row (it aims the wipe) or on the plus is not outside
        window.addEventListener('scroll', follow, true);
        window.addEventListener('resize', follow);
        document.addEventListener('pointerdown', away);
        return () => {
            window.removeEventListener('scroll', follow, true);
            window.removeEventListener('resize', follow);
            document.removeEventListener('pointerdown', away);
        };
    }, [wipe?.kind, wipe?.i]);
    /* the add plus is the wipe: while a row is active it morphs into the cross and slides down to that row (its
       centre goes to --wipe-y), does the delete, and morphs back home once the pointer lets go. Every morph picks a
       different variation (which stroke takes which diagonal, turning which way, each on its own clock and tone). */
    const wipeRef = reactExports.useRef(null);
    wipeRef.current = wipe;
    const ownId = wp.id;
    // a piece whose wipe is still live (parked, or hovered again) takes the plus back when it is free or was torn down
    const [beat, setBeat] = reactExports.useState(0);
    const reclaim = () => { if (wipeRef.current && (plusOwner !== ownId || !document.documentElement.classList.contains('plus-wipe'))) setBeat((n) => n + 1); };
    reactExports.useEffect(() => {
        window.addEventListener('plus-released', reclaim);
        return () => window.removeEventListener('plus-released', reclaim);
    });
    reactExports.useEffect(() => {
        const root = document.documentElement;
        const plus = document.querySelector('.hair-plus');
        if (!wipe || !plus) {
            if (plusOwner === ownId) {
                plusOwner = null;
                root.classList.remove('plus-wipe', 'plus-wipe-flip');
                root.removeAttribute('data-wipe-tip');
                root.classList.add('plus-wipe-out');
                clearTimeout(plusOutTimer);
                plusOutTimer = setTimeout(() => root.classList.remove('plus-wipe-out'), 520);
                setTimeout(() => window.dispatchEvent(new Event('plus-released')), 0);
            }
            return;
        }
        plusOwner = ownId;
        clearTimeout(plusOutTimer);
        if (!root.classList.contains('plus-wipe')) {
            root.classList.remove('plus-wipe-out', 'plus-wipe-flip');
            for (const [k, v] of Object.entries(pickMorph())) root.style.setProperty(k, v);
            root.classList.add('plus-wipe');
        }
        root.style.setProperty('--wipe-y', `${wipe.y}px`);
        const label = plus.getAttribute('aria-label');
        const tip = wipe.kind === 'snap' ? 'delete history' : wipe.kind === 'version' && wp.versions.length > 1 ? 'delete version' : 'delete piece';
        root.setAttribute('data-wipe-tip', tip);
        plus.setAttribute('aria-label', tip);
        const hold = () => { clearTimeout(hideWipe.current); root.classList.toggle('plus-wipe-flip'); };
        const click = (e) => {
            if (!e.target.closest?.('.hair-plus')) return;
            const w = wipeRef.current;
            if (!w) return;
            e.preventDefault();
            e.stopPropagation();
            setWipe(null);
            if (w.kind === 'snap') {
                const sn = snapsRef.current[w.i];
                if (sn) { setPeek((p) => (p === sn ? null : p)); onRemoveSnap(wp.id, sn); }
            } else if (w.kind === 'version' && wp.versions.length > 1) { if (!wp.versions[w.i]?.original) onRemoveVersion(wp.id, w.i); }
            else void onRemove(wp.id);
        };
        plus.addEventListener('pointerenter', hold);
        plus.addEventListener('pointerleave', letGoWipe);
        document.addEventListener('click', click, true);
        return () => {
            plus.removeEventListener('pointerenter', hold);
            plus.removeEventListener('pointerleave', letGoWipe);
            document.removeEventListener('click', click, true);
            if (plusOwner === ownId) { if (label == null) plus.removeAttribute('aria-label'); else plus.setAttribute('aria-label', label); }
        };
    }, [wipe?.y, wipe?.i, wipe?.kind, !!wipe, beat]);
    reactExports.useEffect(() => () => {
        clearTimeout(hideWipe.current);
        if (plusOwner === ownId) { plusOwner = null; document.documentElement.classList.remove('plus-wipe', 'plus-wipe-flip'); document.documentElement.removeAttribute('data-wipe-tip'); }
    }, []);
    return jsxRuntimeExports.jsxs('section', {
        ref: sectionRef,
        className: `story${open ? ' open' : ''} draft-story${PIECES.find((p) => p.id === wp.id)?.dialogue ? ' dialogue' : ''}`,
        id: wp.id,
        style: layoutStyle,
        'data-layout': layout,
        onFocus: () => onActive(wp.id),
        onBlur: (e) => {
            if (!e.currentTarget.contains(e.relatedTarget)) onActive(null);
        },
        children: [
            jsxRuntimeExports.jsxs('div', {
                className: 'story-head',
                ref: headRef,
                onPointerEnter: aim,
                onPointerMove: aim,
                onPointerDown: aim,
                onPointerLeave: letGoWipe,
                children: [
                    jsxRuntimeExports.jsxs('span', {
                        className: 'gutter',
                        children: [
                            '\u00A0',
                            jsxRuntimeExports.jsx('button', {
                                type: 'button',
                                className: `fold-dot${shared ? ' shared' : ''}`,
                                onClick: () => {
                                    if (!shareHeld.current) onToggle();
                                },
                                onPointerDown: sharePress,
                                onPointerUp: shareRelease,
                                onPointerLeave: shareRelease,
                                onContextMenu: (e) => {
                                    if (shareHeld.current) e.preventDefault();
                                },
                                'aria-expanded': open,
                                'aria-label': shared
                                    ? `${v.title || 'piece'} is shared - hover copies the link, hold revokes it`
                                    : (open ? 'fold piece' : 'unfold piece'),
                                onPointerEnter: (e) => { if (shared && e.pointerType === 'mouse') onShareHover?.(); },
                                children: shared ? '\u2022' : '\u00B7',
                            }),
                            jsxRuntimeExports.jsxs('span', { className: `middot-wrap${shareNotice?.kind === 'ready' ? ' ready' : ''}`, 'aria-hidden': shareNotice?.kind === 'ready' ? undefined : 'true', children: [jsxRuntimeExports.jsx('span', { className: 'share-tip', ref: shareTipRef, 'aria-hidden': 'true' }), shareNotice?.kind === 'ready' && jsxRuntimeExports.jsx('input', { className: 'share-url-inline', ref: shareFieldRef, readOnly: true, value: shareNotice.url, 'aria-label': 'share link - copy it by hand', onCopy: () => onShareNoticeCopied?.(), onKeyDown: (e) => { if (e.key === 'Escape') onShareNoticeDone?.(); }, onBlur: () => onShareNoticeDone?.() })] }),
                        ],
                    }),
                    jsxRuntimeExports.jsxs('span', {
                        className: `story-head-main draft-head-main${peek ? ' peeking' : ''}`,
                        children: [
                            jsxRuntimeExports.jsx(
                                EditableTitle,
                                {
                                    id: wp.id,
                                    title: v.title,
                                    register: register,
                                    onInput: () => { onEditInput(wp.id); typingPing(); },  // ruling 23:18 (patch 2)
                                },
                                `t-${wp.seat}`,
                            ),
                            peek &&
                                jsxRuntimeExports.jsx('span', {
                                    className: 'story-title peek-title',
                                    'aria-hidden': 'true',
                                    children: peek.title || '',
                                }),
                    jsxRuntimeExports.jsxs('span', {
                        className: 'version-stack',
                        children: [
                            wp.versions.map((ver, i) =>
                                jsxRuntimeExports.jsx(
                                    'span',
                                    {
                                        className: i === wp.current ? 'vrow current' : 'vrow',
                                        children: [
                                            jsxRuntimeExports.jsxs('span', {
                                            className: 'vrow-inner',
                                            onPointerEnter: (e) => { if (e.pointerType === 'mouse') setHoverV(i); },
                                            onPointerLeave: (e) => { if (e.pointerType === 'mouse') setHoverV(null); },
                                            children: [
                                                jsxRuntimeExports.jsx(
                                                    'span',
                                                    {
                                                        className: `gutter num${i !== wp.current && hoverV === i ? ' serial-on' : ''}`,
                                                        'aria-hidden': 'true',
                                                        children:
                                                            i === wp.current && hoverV !== i
                                                                ? String(num).padStart(3, '0') +
                                                                  '\u00A0\u00A0\u00A0'
                                                                : hoverV === i
                                                                  ? [
                                                                        jsxRuntimeExports.jsx('span', { className: 'vpre', key: 'v', children: 'v\u00A0' }),
                                                                        String(wp.versions.length - i).padStart(3, '0') +
                                                                            '\u00A0\u00A0\u00A0',
                                                                    ]
                                                                  : '\u00A0',
                                                    },
                                                    'gutter',
                                                ),
                                            jsxRuntimeExports.jsx('button', {
                                                type: 'button',
                                                tabIndex: open || i === wp.current ? 0 : -1,
                                                className:
                                                    i === wp.current
                                                        ? 'story-when version current'
                                                        : 'story-when version',
                                                onClick: () => { setPicked(true); onLoadVersion(wp.id, i); },
                                                onMouseEnter: () => setHoverV(i),
                                                onMouseLeave: () => setHoverV(null),
                                                children: whenCellNodes(
                                                    hoverV === i && ver.born !== ver.when ? ver.born : ver.when,
                                                ),
                                            }),
                                            ],
                                                },
                                                'inner',
                                            ),
                                        ],
                                    },
                                    ver.vid,
                                ),
                            ),
                            jsxRuntimeExports.jsx('span', {
                                className: 'vrow add',
                                onPointerEnter: (e) => {
                                    if (e.pointerType !== 'mouse') return;
                                    const button = e.currentTarget.querySelector('.version-add');
                                    if (!button) return;
                                    button.classList.remove('reveal-h-first', 'reveal-v-first');
                                    button.classList.add(randomUnit() < 0.5 ? 'reveal-h-first' : 'reveal-v-first');
                                },
                                onPointerLeave: (e) => {
                                    if (e.pointerType !== 'mouse') return;
                                    e.currentTarget.querySelector('.version-add')?.classList.remove('reveal-h-first', 'reveal-v-first');
                                },
                                onPointerDown: (e) => {
                                    if (e.pointerType !== 'touch') return;
                                    const button = e.currentTarget.querySelector('.version-add');
                                    if (!button || button.classList.contains('touch-revealed')) return;
                                    button.classList.add('touch-revealed');
                                    button.classList.add(randomUnit() < 0.5 ? 'reveal-h-first' : 'reveal-v-first');
                                    e.preventDefault();
                                },
                                children: jsxRuntimeExports.jsx('span', {
                                    className: 'vrow-inner',
                                    children: jsxRuntimeExports.jsx('button', {
                                        type: 'button',
                                        tabIndex: open ? 0 : -1,
                                        className: 'version-add',
                                        'aria-label': 'new version',
                                        'data-tip': 'new version',
                                        'data-tip-dir': 'ltr-right',
                                        onFocus: (e) => {
                                            const button = e.currentTarget;
                                            button.classList.remove('touch-revealed', 'reveal-h-first', 'reveal-v-first');
                                            button.classList.add(randomUnit() < 0.5 ? 'reveal-h-first' : 'reveal-v-first');
                                        },
                                        onBlur: (e) => e.currentTarget.classList.remove('reveal-h-first', 'reveal-v-first'),
                                        onClick: (e) => {
                                            e.currentTarget.classList.remove('touch-revealed', 'reveal-h-first', 'reveal-v-first');
                                            onDuplicate(wp.id);
                                        },
                                    }),
                                }),
                            }),
                        ],
                    }),
                        ],
                    }),
                ],
            }),
            jsxRuntimeExports.jsx('div', {
                className: 'story-fold',
                children: jsxRuntimeExports.jsxs('div', {
                    className: 'story-body',
                    children: [
                        jsxRuntimeExports.jsx('div', {
                            className: peek ? 'snap-hidden' : undefined,
                            children: jsxRuntimeExports.jsx(
                                EditableBody,
                                {
                                    id: wp.id,
                                    lines: v.lines,
                                    audio: wp.audio,
                                    register: register,
                                    onInput: () => { onEditInput(wp.id); typingPing(); },  // ruling 23:18 (patch 2)
                                },
                                `b-${wp.seat}`,
                            ),
                        }),
                        peek &&
                            jsxRuntimeExports.jsxs('div', {
                                className: 'snap-peek',
                                'aria-label': `past self, ${peek.at}`,
                                children: [
                                    jsxRuntimeExports.jsx('div', {
                                        className: 'story-text',
                                        children: (peek.lines.length ? peek.lines : ['']).map(
                                            (line, i) =>
                                                jsxRuntimeExports.jsx(
                                                    'p',
                                                    {
                                                        children: line
                                                            ? jsxRuntimeExports.jsx(ParaText, {
                                                                  text: line,
                                                              })
                                                            : null,
                                                    },
                                                    i,
                                                ),
                                        ),
                                    }),
                                ],
                            }),
                        audioAt(wp.audio, null, v.lines.length).length > 0 &&
                            jsxRuntimeExports.jsx('div', {
                                className: 'story-audio',
                                children: audioAt(wp.audio, null, v.lines.length).map(a =>
                                    jsxRuntimeExports.jsx(
                                        AudioPart,
                                        { id: `${wp.id}-${a.index}`, src: a.src, label: a.label },
                                        a.index,
                                    ),
                                ),
                            }),
                        wp.note &&
                            jsxRuntimeExports.jsx('div', {
                                className: 'story-note',
                                children: wp.note,
                            }),
                        hasHistory || hadHistory.current
                            ? jsxRuntimeExports.jsx(HistoryEnd, { snaps, open, peek, setPeek, onRestore: (snap) => onRestore(wp.id, snap) })
                            : (wp.hasEndmark || resting) &&
                              /* closure control: the mark is a button in the same control language as the
                                 history mark. The gesture toggles hasEndmark through the app's piece-update
                                 path (onToggleEndmark); pointerdown is swallowed so the editor keeps its
                                 caret and focus, a text selection in progress is not a gesture, and
                                 invalid/missing piece data leaves the state unchanged. The inline reset
                                 stands in for a stylesheet rule so the packet's diff stays in this file. */
                              jsxRuntimeExports.jsx('button', {
                                  type: 'button',
                                  className: wp.hasEndmark ? 'endmark' : 'endmark resting',
                                  style: { background: 'none', border: 0, padding: 0, font: 'inherit', color: 'inherit', cursor: 'pointer', textAlign: 'left', display: 'block', width: 'fit-content', minWidth: '32px', minHeight: '32px' }, // block like the p it replaces; >=32px tap box, glyphs unmoved
                                  'aria-pressed': !!wp.hasEndmark,
                                  'aria-label': wp.hasEndmark ? 'reopen piece' : 'close piece',
                                  onPointerDown: (e) => e.preventDefault(),
                                  onClick: () => {
                                      const sel = window.getSelection?.();
                                      if (sel && !sel.isCollapsed) return;
                                      if (typeof wp.hasEndmark !== 'boolean') return;
                                      onToggleEndmark?.(wp.id);
                                  },
                                  children: '\u00B7 \u00B7',
                              }),
                    ],
                }),
            }),
        ],
    });
}
/*
 * placePanel - put a pop-out panel (type shelf, sync) to the left of its button and keep it
 * on screen: centred on the button where it fits, pushed in where it doesn't, and never wider
 * than the room left of the button (narrow phones).
 */
function placePanel(list, widget) {
    const w = widget.getBoundingClientRect();
    list.style.maxWidth = `${Math.max(120, w.left - 10 - 8)}px`;
    const h = list.offsetHeight;
    const top = Math.max(12, Math.min(w.top + w.height / 2 - h / 2, window.innerHeight - h - 12));
    list.style.top = `${top}px`;
    list.style.right = `${window.innerWidth - w.left + 10}px`;
}
/*
 * AxisKnobs - the knobs of a variable face, shown under its name in the face list.
 * One thin line per axis, named in the list's own words (weight, width, softness...), with the value
 * beside it. Turning a knob changes the text live without re-rendering the page (onLive sets the CSS
 * variable directly); letting go keeps the value (onDone), which saves and syncs it with the settings.
 * Double-click (or double-tap) a knob's name to put that axis back to the font's default.
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
function prepareCommitRange(el, range) {
    if (!el || !el.isConnected) return { ok: false, reason: 'no-editor' };
    if (!range) return { ok: false, reason: 'no-range' };
    if (!range.startContainer.isConnected || !range.endContainer.isConnected || !el.contains(range.startContainer) || !el.contains(range.endContainer))
        return { ok: false, reason: 'range-outside-editor' };
    const clone = range.cloneRange();
    clone.collapse(false);
    return { ok: true, range: clone };
}
// Explicit capability: older commitText implementations must never silently accept atomic options.
function commitTextAtomic(el, text, { range = null } = {}) {
    return commitText(el, text, { commit: false, range, atomic: true });
}
export { commitTextAtomic, storeSetChecked, prepareCommitRange, commitText, pickMorph, HistoryEnd, pieceSnapshots, ERA_TIPS, FxPalette, ParaText, WorkStory, attachCommit, attachTypeSound, placePanel, readParas, readTitle, storeGet, storeSet };



