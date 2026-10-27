import {readFileSync} from 'node:fs';
import {packState,readScopedState} from '../state-scope.js';
const app=readFileSync(new URL('../app.js',import.meta.url),'utf8');
export const helperSrc=app.slice(app.indexOf('    const HELD_PREFIX'),app.indexOf('    reactExports.useEffect(() => {\n        const onStorage'));
const ls={};
export const custodyCtx=()=>({TextEncoder,DataView,Uint8Array,reactExports:{useRef:v=>({current:v})},STATE_KEY:'middots-state',localStorage:{getItem:k=>ls[k]??null,setItem:(k,v)=>{ls[k]=v}},packState,readScopedState});
