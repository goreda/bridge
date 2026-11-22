// Complete lexical unresolved-name scan of actual WT source. No source execution/network.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {parse,analyze}=require('./scope-parser.cjs');
const source=fs.readFileSync(process.env.WT_GLOBAL_SOURCE||path.resolve(__dirname,'../../Resources/vendor/wt_server/wt_server.mjs'),'utf8');
const globals=new Set(['process','Buffer','console','setTimeout','clearTimeout','setInterval','clearInterval','setImmediate','clearImmediate','URL','Map','Set','WeakMap','WeakSet','Array','Object','String','Number','Boolean','Math','Date','JSON','Promise','Error','TypeError','RangeError','Uint8Array','Uint32Array','Float64Array','ArrayBuffer','DataView','Int32Array','Infinity','NaN','undefined','parseInt','parseFloat','isNaN','isFinite','RegExp','Symbol','BigInt','globalThis','encodeURIComponent','performance','AbortController']);
function missing(text){const ast=parse(text,{ecmaVersion:2022,sourceType:'module',ranges:true});return [...new Set(analyze(ast,{ecmaVersion:2022,sourceType:'module'}).globalScope.through.map(r=>r.identifier.name).filter(n=>!globals.has(n)))].sort();}
assert.deepEqual(missing(source),[],'all lexical unresolved identifiers accounted for');
assert.deepEqual(missing(source.replace('const RING_PIN_HEAD = 2, RING_PIN_TAIL = 3, RING_PIN_MAX = 5;','')),['RING_PIN_HEAD','RING_PIN_MAX','RING_PIN_TAIL']);
assert(missing(source+'\nconst witness=NEVER_DEFINED_WT_TEST;').includes('NEVER_DEFINED_WT_TEST'));
console.log('PASS full-file lexical scope unresolved names; missing ring and arbitrary-new-name mutants RED; TDZ separately executed by startup-order test');
