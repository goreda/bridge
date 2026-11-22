// Torrent metadata only. No torrent payloads, HTML, cookies or executable page content.
const hex=/^[a-f0-9]{40}$/i;
const digits=/^(0|[1-9]\d*)$/;
const number=(value,label)=>{
 if(!((typeof value==='string'&&digits.test(value))||(typeof value==='number'&&Number.isSafeInteger(value)&&value>=0)))throw Error(`layout:${label}`);
 const n=Number(value);if(!Number.isSafeInteger(n))throw Error(`layout:${label}`);return n;
};
const title=(x,label)=>{if(typeof x!=='string'||!x.trim()||x.length>300)throw Error(`layout:${label}`);return x.trim()};
const magnet=(hash,name)=>`magnet:?xt=urn:btih:${hash}&dn=${encodeURIComponent(name)}`;
const row=(source,name,rawHash,size,seeds,leeches,uploadedAt,detailUrl)=>{
 const hash=String(rawHash).toLowerCase();if(!hex.test(hash))throw Error(`layout:${source}:hash`);
 return {title:title(name,`${source}:title`),sizeBytes:number(size,`${source}:size`),seeds:number(seeds,`${source}:seeds`),leeches:number(leeches,`${source}:leeches`),magnetUri:magnet(hash,name),infoHash:hash,uploadedAt,uploadedLabel:null,uploadedAtEstimated:false,source,detailUrl};
};
export function parseApibay(data){
 if(!Array.isArray(data)||data.length>100)throw Error('layout:apibay:envelope');
 if(data.length===1&&data[0]?.id==='0'&&data[0]?.name==='No results returned'&&/^0{40}$/.test(data[0]?.info_hash??''))return [];
 return data.map(x=>{
  if(!x||typeof x!=='object'||!digits.test(String(x.id))||number(x.id,'apibay:id')===0)throw Error('layout:apibay:id');
  const stamp=number(x.added,'apibay:added');const date=new Date(stamp*1000);
  if(!Number.isFinite(date.getTime())||stamp<0||stamp>4102444800)throw Error('layout:apibay:date');
  return row('apibay',x.name,x.info_hash,x.size,x.seeders,x.leechers,date.toISOString(),"");
 });
}
export function parseBitsearch(data){
 if(!data||typeof data!=='object'||data.success!==true||!Array.isArray(data.results)||data.results.length>20||!data.pagination||typeof data.pagination!=='object')throw Error('layout:bitsearch:envelope');
 return data.results.map(x=>{
  if(!x||typeof x.id!=='string'||!/^[a-f0-9]{24}$/i.test(x.id))throw Error('layout:bitsearch:id');
  const date=new Date(x.updatedAt);if(typeof x.updatedAt!=='string'||!/^\d{4}-\d\d-\d\dT/.test(x.updatedAt)||!Number.isFinite(date.getTime()))throw Error('layout:bitsearch:date');
  return row('bitsearch',x.title,x.infohash,x.size,x.seeders,x.leechers,date.toISOString(),"");
 });
}
export function parseMagnetz(data){
 if(!data||typeof data!=='object'||!Array.isArray(data.data)||data.data.length>25||!data.meta||typeof data.meta!=='object')throw Error('layout:magnetz:envelope');
 return data.data.map(x=>{
  if(!x||typeof x.sqid!=='string'||!/^[a-zA-Z0-9]{4,24}$/.test(x.sqid))throw Error('layout:magnetz:id');
  const date=new Date(x.created_at);if(typeof x.created_at!=='string'||!/^\d{4}-\d\d-\d\dT/.test(x.created_at)||!Number.isFinite(date.getTime()))throw Error('layout:magnetz:date');
  const r=row('magnetz',x.name,x.info_hash,x.size,x.seeders,x.leechers,date.toISOString(),"");
  if(typeof x.magnet_link!=='string'||new URL(x.magnet_link).searchParams.get('xt')?.toLowerCase()!==`urn:btih:${r.infoHash}`)throw Error('layout:magnetz:magnet');
  return r;
 });
}
const xmlText=s=>s.replace(/&(?:amp|quot|apos|lt|gt);/g,m=>({'&amp;':'&','&quot;':'"','&apos;':"'",'&lt;':'<','&gt;':'>'})[m]);
const xmlField=(item,tag)=>xmlText(item.match(new RegExp(`<${tag}(?:\\s+[^>]*)?>([\\s\\S]*?)<\\/${tag}>`,'i'))?.[1]??'').trim();
export function parseBT4GRSS(xml){
 if(typeof xml!=='string'||xml.length>1_000_000||!/^\s*<rss\s+version="2\.0"/.test(xml))throw Error('layout:bt4g:rss');
 const items=[...xml.matchAll(/<item>[\s\S]*?<\/item>/g)].map(x=>x[0]);if(items.length>100)throw Error('layout:bt4g:items');
 return items.map(item=>{
  const name=title(xmlField(item,'title'),'bt4g:title');const direct=xmlField(item,'link');
  const hash=new URL(direct).searchParams.get('xt')?.match(/^urn:btih:([a-f0-9]{40})$/i)?.[1]?.toLowerCase();
  if(!hash||!direct.startsWith('magnet:?'))throw Error('layout:bt4g:magnet');
  const guid=new URL(xmlField(item,'guid'));if(guid.origin!=='https://bt4gprx.com'||!/^\/magnet\/[a-zA-Z0-9]+$/.test(guid.pathname))throw Error('layout:bt4g:guid');
  const date=new Date(xmlField(item,'pubDate'));if(!Number.isFinite(date.getTime()))throw Error('layout:bt4g:date');
  // The RSS description is a four-line CDATA payload: title, size,
  // category, hash. Only accept the size when the trailing hash matches
  // the magnet, so changed markup cannot silently mislabel another row.
  const description=item.match(/<description><!\[CDATA\[([\s\S]*?)\]\]><\/description>/i)?.[1];
  const parts=description?.split(/<br\s*\/?>/i).map(x=>x.trim());
  if(parts?.length!==4||parts[3].toLowerCase()!==hash)throw Error('layout:bt4g:description');
  const displaySize=parts[1].match(/^(\d+(?:\.\d+)?)\s*(B|KB|MB|GB|TB)$/i);
  if(!displaySize)throw Error('layout:bt4g:size');
  const exponent={b:0,kb:1,mb:2,gb:3,tb:4}[displaySize[2].toLowerCase()];
  const sizeBytes=Math.round(Number(displaySize[1])*1000**exponent);
  if(!Number.isSafeInteger(sizeBytes))throw Error('layout:bt4g:size');
  return {title:name,sizeBytes,seeds:null,leeches:null,magnetUri:direct,infoHash:hash,uploadedAt:date.toISOString(),uploadedLabel:null,uploadedAtEstimated:false,source:'bt4g',detailUrl:guid.href};
 });
}
export function parseNyaaRSS(xml){
 if(typeof xml!=='string'||xml.length>1_000_000||!/<rss\b/.test(xml))throw Error('layout:nyaa:rss');
 const items=[...xml.matchAll(/<item>[\s\S]*?<\/item>/g)].map(x=>x[0]);if(items.length>100)throw Error('layout:nyaa:items');
 return items.map(item=>{
  const name=title(xmlField(item,'title'),'nyaa:title'), hash=xmlField(item,'nyaa:infoHash');
  const seed=xmlField(item,'nyaa:seeders'),leech=xmlField(item,'nyaa:leechers');
  const size=xmlField(item,'nyaa:size').match(/^(\d+(?:\.\d+)?)\s*(B|KiB|MiB|GiB|TiB)$/i);
  if(!size)throw Error('layout:nyaa:size');
  const factor={b:0,kib:1,mib:2,gib:3,tib:4}[size[2].toLowerCase()];
  const date=new Date(xmlField(item,'pubDate'));if(!Number.isFinite(date.getTime()))throw Error('layout:nyaa:date');
  const r=row('nyaa',name,hash,Math.round(Number(size[1])*1024**factor),seed,leech,date.toISOString(),'');
  const direct=xmlField(item,'link');if(!/^https:\/\/nyaa\.si\/(view|download)\/\d+(?:\.torrent)?$/.test(direct))throw Error('layout:nyaa:link');return r;
 });
}
const normalize=s=>s.toLocaleLowerCase('en-US').normalize('NFKD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-z0-9]+/g,' ');
// Reject executable-named payloads before relevance, dedupe and sort.
// Torrent metadata cannot prove the actual payload is safe.
export const hasExecutableTitle=s=>/\.exe(?![a-z0-9])/i.test(s);
export const tokens=s=>normalize(s).trim().split(/\s+/).filter(Boolean);
export function relevant(rows,query){
 const q=tokens(query);if(!q.length)return [];
 return rows.filter(r=>{const words=tokens(r.title);return q.every(term=>words.includes(term))});
}
export function mergeAndSort(groups,key='seeds',descending=true,query=''){
 if(!['title','source','seeds','sizeBytes','uploadedAt'].includes(key))throw Error('invalid sort');
 const allowed=groups.flat().filter(r=>!hasExecutableTitle(r.title));
 const seen=new Map();for(const r of (query?relevant(allowed,query):allowed)){const old=seen.get(r.infoHash);if(!old||(r.seeds??-1)>(old.seeds??-1))seen.set(r.infoHash,r)}
 return [...seen.values()].sort((a,b)=>{
  if(key==='title'||key==='source'){
   const order=a[key].localeCompare(b[key],undefined,{numeric:true,sensitivity:'base'});
   return (descending?-order:order)||a.title.localeCompare(b.title)||a.infoHash.localeCompare(b.infoHash);
  }
  const av=key==='uploadedAt'?Date.parse(a.uploadedAt):a[key],bv=key==='uploadedAt'?Date.parse(b.uploadedAt):b[key];
  const x=Number.isFinite(av)?av:null,y=Number.isFinite(bv)?bv:null;
  if(x===null||y===null){if(x===null&&y!==null)return 1;if(y===null&&x!==null)return -1;return (b.seeds??-1)-(a.seeds??-1)||a.title.localeCompare(b.title)}
  return (descending?y-x:x-y)||(b.seeds??-1)-(a.seeds??-1)||a.title.localeCompare(b.title);
 });
}

// Knaben's public JSON search: title/bytes/seeders/date/hash are direct fields.
export function parseKnaben(data){
 if(!data||typeof data!=='object'||!Array.isArray(data.hits)||data.hits.length>50||!data.total||typeof data.total!=='object')throw Error('layout:knaben:envelope');
 return data.hits.map(x=>{
  if(!x||typeof x!=="object")throw Error("layout:knaben:item");
  const detail=(typeof x.details==="string"&&x.details.startsWith("https://"))?x.details:"";
  const date=new Date(x.date);if(typeof x.date!=='string'||!/^\d{4}-\d\d-\d\dT/.test(x.date)||!Number.isFinite(date.getTime()))throw Error('layout:knaben:date');
  const r=row('knaben',x.title,x.hash,x.bytes,x.seeders,x.peers,date.toISOString(),detail);
  if(typeof x.magnetUrl!=='string'||!x.magnetUrl.startsWith('magnet:?')||new URL(x.magnetUrl).searchParams.get('xt')?.toLowerCase()!==`urn:btih:${r.infoHash}`)throw Error('layout:knaben:magnet');
  return r;
 });
}

// EZTV offers latest pages and IMDb lookup, not a full-text search endpoint.
// No title match on its newest page means no result there, not a catalogue miss.
export function parseEZTV(data){
 if(!data||typeof data!=='object'||!Array.isArray(data.torrents)||data.torrents.length>100||!Number.isSafeInteger(data.torrents_count)||!Number.isSafeInteger(data.limit)||!Number.isSafeInteger(data.page))throw Error('layout:eztv:envelope');
 return data.torrents.map(x=>{
  if(!x||typeof x!=='object'||!Number.isSafeInteger(x.id)||x.id<1)throw Error('layout:eztv:id');
  const stamp=number(x.date_released_unix,'eztv:date');
  const date=new Date(stamp*1000);if(!Number.isFinite(date.getTime())||stamp>4102444800)throw Error('layout:eztv:date');
  const r=row('eztv',x.title,x.hash,x.size_bytes,x.seeds,x.peers,date.toISOString(),'');
  if(typeof x.magnet_url!=='string'||!x.magnet_url.startsWith('magnet:?')||new URL(x.magnet_url).searchParams.get('xt')?.toLowerCase()!==`urn:btih:${r.infoHash}`)throw Error('layout:eztv:magnet');
  return r;
 });
}


// UDP tracker scrape (BEP 15): fills seeds/leeches for rows whose source
// cannot report swarm health (bt4g RSS). Runs fully local - no website
// access, so no Cloudflare involvement. Trackers come from each row's own
// magnet URI.
import dgram from 'node:dgram';
import crypto from 'node:crypto';
const scrapeOne=(tracker,infoHash,timeoutMs)=>new Promise(resolve=>{
 const m=tracker.match(/^udp:\/\/([^:/]+):(\d+)/);
 if(!m)return resolve(null);
 const sock=dgram.createSocket('udp4');
 let txConn=null,txScr=null;
 const finish=v=>{clearTimeout(timer);try{sock.close()}catch{}resolve(v)};
 const timer=setTimeout(()=>finish(null),timeoutMs);
 sock.on('error',()=>finish(null));
 sock.on('message',msg=>{
  try{
   const action=msg.readUInt32BE(0),tx=msg.readUInt32BE(4);
   if(action===0&&tx===txConn){
    const connId=msg.subarray(8,16);
    txScr=crypto.randomBytes(4).readUInt32BE();
    const head=Buffer.alloc(16);connId.copy(head);head.writeUInt32BE(2,8);head.writeUInt32BE(txScr,12);
    sock.send(Buffer.concat([head,Buffer.from(infoHash,'hex')]),Number(m[2]),m[1]);
   }else if(action===2&&tx===txScr){
    finish({seeds:msg.readUInt32BE(8),completed:msg.readUInt32BE(12),leeches:msg.readUInt32BE(16)});
   }else if(action===3){finish(null)}
  }catch{finish(null)}
 });
 const connReq=Buffer.alloc(16);
 connReq.writeBigUInt64BE(0x41727101980n,0);connReq.writeUInt32BE(0,8);
 txConn=crypto.randomBytes(4).readUInt32BE();connReq.writeUInt32BE(txConn,12);
 sock.send(connReq,Number(m[2]),m[1]);
});
const trackersOf=uri=>{try{return new URL(uri).searchParams.getAll('tr').filter(t=>t.startsWith('udp://'))}catch{return[]}};
// Enrich up to maxRows rows that lack seed counts. Best count across
// trackers wins; unanswered trackers simply contribute nothing.
export async function enrichSeeds(rows,{maxRows=25,perRowTrackers=3,timeoutMs=4000}={}){
 const targets=rows.filter(r=>r.seeds==null).slice(0,maxRows);
 await Promise.all(targets.map(async r=>{
  const trackers=trackersOf(r.magnetUri).slice(0,perRowTrackers);
  if(!trackers.length)return;
  const answers=(await Promise.all(trackers.map(t=>scrapeOne(t,r.infoHash,timeoutMs)))).filter(Boolean);
  if(!answers.length)return;
  r.seeds=Math.max(...answers.map(a=>a.seeds));
  r.leeches=Math.max(...answers.map(a=>a.leeches));
  r.swarmSource='tracker-scrape';
 }));
 return rows;
}

// UIndex search results are HTML (search.php is Cloudflare-walled for plain
// fetch; the RSS feed is a paid "RSS Pro" feature). This parser consumes the
// results <table class="sr-table"> markup produced by any route that can
// render the page. Fail-closed like the other parsers: any layout drift
// throws layout:uindex:* instead of mislabeling rows.
const uindexRelToISO=rel=>{
 const m=rel.match(/^(\d+(?:\.\d+)?)\s*(minute|hour|day|week|month|year)s?\s+ago$/i);
 if(!m)throw Error('layout:uindex:uploaded');
 const n=Number(m[1]);
 const days={minute:n/1440,hour:n/24,day:n,week:7*n,month:30.44*n,year:365.25*n}[m[2].toLowerCase()];
 return new Date(Date.now()-days*86400000).toISOString();
};
export function parseUindex(html){
 if(typeof html!=='string'||html.length>2_000_000)throw Error('layout:uindex:envelope');
 const table=html.match(/<table[^>]*class="sr-table"[^>]*>([\s\S]*?)<\/table>/i);
 if(!table)throw Error('layout:uindex:table');
 const rows=[...table[1].matchAll(/<tr>([\s\S]*?)<\/tr>/g)].map(x=>x[1]).filter(r=>r.includes('sr-torrent-link'));
 if(rows.length>100)throw Error('layout:uindex:items');
 return rows.map(r=>{
  const magnetHref=r.match(/<a href="(magnet:\?[^"]+)" class="sr-magnet"/)?.[1];
  if(!magnetHref)throw Error('layout:uindex:magnet');
  const hash=new URL(magnetHref.replace(/&amp;/g,'&')).searchParams.get('xt')?.match(/^urn:btih:([a-f0-9]{40})$/i)?.[1]?.toLowerCase();
  if(!hash)throw Error('layout:uindex:hash');
  const link=r.match(/<a href="\/details\.php\?id=(\d+)" class="sr-torrent-link" title="([^"]*)"/);
  if(!link)throw Error('layout:uindex:title');
  const name=title(xmlText(link[2]),'uindex:title');
  const sizeTxt=r.match(/<td class="sr-col-size">([^<]+)<\/td>/)?.[1]?.trim();
  const size=sizeTxt?.match(/^(\d+(?:\.\d+)?)\s*(B|KB|MB|GB|TB)$/i);
  if(!size)throw Error('layout:uindex:size');
  const exponent={b:0,kb:1,mb:2,gb:3,tb:4}[size[2].toLowerCase()];
  const sizeBytes=Math.round(Number(size[1])*1000**exponent);
  if(!Number.isSafeInteger(sizeBytes))throw Error('layout:uindex:size');
  const rel=r.match(/<td class="sr-col-uploaded"[^>]*>([^<]+)<\/td>/)?.[1]?.trim();
  if(!rel)throw Error('layout:uindex:uploaded');
  const seeds=r.match(/<span class="sr-seed">(\d+)<\/span>/)?.[1];
  const leeches=r.match(/<span class="sr-leech">(\d+)<\/span>/)?.[1];
  if(seeds==null||leeches==null)throw Error('layout:uindex:peers');
  const out=row('uindex',name,hash,sizeBytes,seeds,leeches,uindexRelToISO(xmlText(rel)),`https://uindex.org/details.php?id=${link[1]}`);
  out.uploadedAtEstimated=true; // search page shows only relative age ("9.4 months ago")
  return out;
 });
}

