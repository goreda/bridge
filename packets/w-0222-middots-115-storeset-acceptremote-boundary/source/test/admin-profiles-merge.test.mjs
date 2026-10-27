import test from 'node:test';
import assert from 'node:assert/strict';
import { mergeStates } from '../state-merge.js';
const lane = (o = {}) => ({ textFace: 'fragment-mono', indexFace: 'fragment-mono', textPt: 10, indexPt: 10, textAxes: {}, indexAxes: {}, lh: 1.5, hz: 0, textWidthEm: 29, ...o });
const ap = (desktop) => ({ version: 1, profiles: { desktop } });
const doc = (adminProfiles) => ({ ...(adminProfiles === undefined ? {} : { adminProfiles }), pieces: [] });
const saved = ap(lane({ textFace: 'owner-face', textPt: 13 }));
test('a session without adminProfiles keeps the service copy', () => {
  assert.deepEqual(mergeStates(doc(saved), doc(), doc(saved)).state.adminProfiles, saved);
});
test('fresh browser after logout: local defaults never beat the saved account value', () => {
  const d = mergeStates(null, doc(ap(lane())), doc(saved)).state.adminProfiles.profiles.desktop;
  assert.equal(d.textFace, 'owner-face'); assert.equal(d.textPt, 13);
});
test('first upload: account has no value, local values are kept', () => {
  assert.deepEqual(mergeStates(null, doc(saved), doc()).state.adminProfiles, saved);
});
test('an edit on this device wins over an unchanged service copy', () => {
  const r = mergeStates(doc(saved), doc(ap(lane({ textFace: 'new-face', textPt: 13 }))), doc(saved));
  assert.equal(r.state.adminProfiles.profiles.desktop.textFace, 'new-face'); assert.equal(r.localChanged, true);
});
test('edits to different fields on two devices both survive', () => {
  const d = mergeStates(doc(saved), doc(ap(lane({ textFace: 'owner-face', textPt: 14 }))), doc(ap(lane({ textFace: 'other-face', textPt: 13 })))).state.adminProfiles.profiles.desktop;
  assert.equal(d.textPt, 14); assert.equal(d.textFace, 'other-face');
});
test('a corrupt service value is held as it is', () => {
  const bad = { version: 1, profiles: { desktop: { textPt: 'x' } } };
  const r = mergeStates(doc(saved), doc(saved), doc(bad));
  assert.deepEqual(r.state.adminProfiles, bad); assert.equal(r.adminConflicts[0].reason, 'remote-corrupt-held');
});
test('admin conflicts never enter the piece conflict list', () => {
  const r = mergeStates(doc(saved), doc(ap(lane({ textPt: 15 }))), doc(ap(lane({ textPt: 16 }))));
  assert.equal(r.conflicts.length, 0); assert.equal(r.adminConflicts.length, 1);
});
test('an identical merged value is not a local change', () => {
  assert.equal(mergeStates(doc(saved), doc(saved), doc(saved)).localChanged, false);
});

// Forward-compatible keys with different insertion order are a semantic no-op.
test('admin property order does not schedule a write', () => {
    const remote={version:1,profiles:{desktop:{textPt:12,extra:{z:1,a:2}}},future:{z:3,a:4}};
    const local={future:{a:4,z:3},profiles:{desktop:{extra:{a:2,z:1},textPt:12}},version:1};
    const result=mergeStates({adminProfiles:remote,pieces:[]},{adminProfiles:local,pieces:[]},{adminProfiles:remote,pieces:[]});
    assert.equal(result.localChanged,false);
    assert.deepEqual(result.adminConflicts,[]);
});

