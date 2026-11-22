// stdin: {query, providers:{apibay?:JSON,bitsearch?:JSON}, failures?:{source:code},sort,descending}
import {parseApibay,parseBitsearch,parseMagnetz,parseBT4GRSS,parseNyaaRSS,parseKnaben,parseEZTV,parseUindex,mergeAndSort,enrichSeeds} from './magnet_search.mjs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
let input='';for await(const chunk of process.stdin){input+=chunk;if(input.length>2_000_000)throw Error('input too large')}
const arg=JSON.parse(input);if(typeof arg.query!=='string'||!arg.query.trim()||arg.query.length>120)throw Error('invalid query');
const providers={},groups=[];
const pending=new Set(Array.isArray(arg.pendingProviders)?arg.pendingProviders:[]);
for(const [key,parse] of [['apibay',parseApibay],['bitsearch',parseBitsearch],['magnetz',parseMagnetz],['bt4g',parseBT4GRSS],['nyaa',parseNyaaRSS],['knaben',parseKnaben],['eztv',parseEZTV]]){
 const raw=arg.providers?.[key];
 if(raw==null){providers[key]=pending.has(key)?{status:'pending'}:{status:'unavailable',reason:arg.failures?.[key]??'no_response'};continue}
 try{const rows=parse(raw);groups.push(rows);providers[key]={status:'ok',parsed:rows.length}}
 catch(e){providers[key]={status:'broken',reason:/^layout:[a-z0-9:-]+$/.test(e.message)?e.message:'parse_error'}}
}
const sort=arg.sort??'seeds',descending=arg.descending!==false;
let merged=mergeAndSort(groups,sort,descending,arg.query);
// Final parse of a search (no providers still fetching): fill missing seed counts
// (bt4g RSS carries none) straight from the swarms via UDP tracker scrape.
// Local only - no website access. Runs once per search, after the last provider settles.
if(pending.size===0){
 // uindex via the local stealth bridge: real Chrome (automation fingerprints
 // stripped) on a persistent gor-owned profile at ~/.gor/browser-profile.
 // Cloudflare clearance accumulates in the profile automatically; no manual
 // steps. Network/browser lives only in bridge_uindex.mjs; parser stays pure.
 // Requires Chrome installed; window parked offscreen. No Swift change:
 // uindex rows land on the final parse, marked unavailable when walled.
 const bridgeScript=fileURLToPath(new URL('bridge_uindex.mjs',import.meta.url));
 const chromePath=process.env.GOR_UINDEX_CHROME||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
 try{
  const html=execFileSync(process.execPath,[bridgeScript,chromePath,arg.query],{timeout:120000,maxBuffer:3_000_000}).toString();
  const urows=parseUindex(html);
  groups.push(urows);providers.uindex={status:'ok',parsed:urows.length};
  merged=mergeAndSort(groups,sort,descending,arg.query);
 }catch(e){
  providers.uindex={status:'unavailable',reason:/WALLED/.test(e.stderr?.toString()??'')?'walled':'fetch_failed'};
 }
}
if(pending.size===0&&merged.some(r=>r.seeds==null)){
 await enrichSeeds(merged,{maxRows:25,perRowTrackers:3,timeoutMs:4000});
 merged=mergeAndSort([merged],sort,descending);
}
console.log(JSON.stringify({schemaVersion:2,results:merged,pendingRows:[],providers}));

