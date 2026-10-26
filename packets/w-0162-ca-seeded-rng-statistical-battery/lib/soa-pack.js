'use strict';
// Struct-of-arrays codec with an explicit stride, for packing records into a Float64Array and back.
// schema: {fields:[names...], stride:int>=fields.length}; unused tail slots are reserved and written as 0.
function checkSchema(s) { if (!s || !Array.isArray(s.fields) || !Number.isInteger(s.stride) || s.stride < s.fields.length || new Set(s.fields).size !== s.fields.length) throw new TypeError('bad schema'); }
function pack(records, schema, out) {
  checkSchema(schema); const need = records.length * schema.stride;
  if (out && out.length < need) throw new RangeError('output buffer too small: ' + out.length + ' < ' + need);
  const buf = out || new Float64Array(need);
  records.forEach((r, i) => { const b = i * schema.stride; schema.fields.forEach((f, k) => { const v = r[f]; if (typeof v !== 'number') throw new TypeError('field ' + f + ' of record ' + i + ' is not a number'); buf[b + k] = v; }); for (let k = schema.fields.length; k < schema.stride; k++) buf[b + k] = 0; });
  return buf;
}
function unpack(buf, count, schema) {
  checkSchema(schema); if (buf.length < count * schema.stride) throw new RangeError('buffer shorter than count*stride');
  return Array.from({ length: count }, (_, i) => Object.fromEntries(schema.fields.map((f, k) => [f, buf[i * schema.stride + k]])));
}
// assertStride(reported, expected): ABI-style guard, throws on mismatch (never coerces).
function assertStride(reported, expected) { if (reported !== expected) throw new RangeError('stride mismatch: ' + reported + ' != ' + expected); }
module.exports = { pack, unpack, assertStride };
