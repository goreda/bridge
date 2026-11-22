import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {parseApibay,parseBitsearch,parseMagnetz,parseBT4GRSS,parseNyaaRSS,parseKnaben,parseEZTV,mergeAndSort} from '../../../Resources/vendor/magnet_search/magnet_search.mjs';
const hash='a'.repeat(40), hash2='b'.repeat(40), date='2026-09-29T09:00:00.000Z';
const magnet=h=>`magnet:?xt=urn:btih:${h}`;
const apibay=[{id:'12',name:'Ubuntu Linux ISO',info_hash:hash,size:'1000',seeders:'12',leechers:'2',added:'1790672400'}];
const bitsearch={success:true,pagination:{page:1},results:[{id:'a'.repeat(24),title:'Ubuntu Linux ISO',infohash:hash2,size:1000,seeders:3,leechers:1,updatedAt:date}]};
const magnetz={meta:{page:1},data:[{sqid:'abcd12',name:'Ubuntu Linux ISO',info_hash:hash,size:1000,seeders:1,leechers:0,created_at:date,magnet_link:magnet(hash)}]};
const knaben={total:{value:1,relation:'eq'},hits:[{title:'Ubuntu Linux ISO',hash,bytes:1000,seeders:12,peers:2,date,details:'https://knaben.xyz/item',magnetUrl:magnet(hash)}]};
const eztv={torrents_count:1,limit:100,page:1,torrents:[{id:1,title:'Ubuntu Linux ISO',hash,size_bytes:'1000',seeds:12,peers:2,date_released_unix:1790672400,magnet_url:magnet(hash)}]};
const nyaa=`<rss version="2.0" xmlns:nyaa="https://nyaa.si/xmlns/nyaa"><channel><item><title>Ubuntu Linux ISO</title><link>https://nyaa.si/view/123</link><pubDate>Tue, 29 Sep 2026 09:00:00 GMT</pubDate><nyaa:infoHash>${hash}</nyaa:infoHash><nyaa:seeders>12</nyaa:seeders><nyaa:leechers>2</nyaa:leechers><nyaa:size>1.0 GiB</nyaa:size></item></channel></rss>`;
const bt4g=readFileSync(new URL('./fixtures/bt4g-rss.xml',import.meta.url),'utf8');
const cli=input=>{const p=spawnSync(process.execPath,[new URL('../../../Resources/vendor/magnet_search/cli.mjs',import.meta.url).pathname],{input:JSON.stringify(input),encoding:'utf8'});assert.equal(p.status,0,p.stderr);return JSON.parse(p.stdout)};
test('direct JSON providers parse validated metadata and hash-bound magnets',()=>{
  for(const rows of [parseApibay(apibay),parseBitsearch(bitsearch),parseMagnetz(magnetz),parseKnaben(knaben),parseEZTV(eztv)]){
    assert.equal(rows.length,1);const [r]=rows;
    assert.equal(new URL(r.magnetUri).searchParams.get('xt'),`urn:btih:${r.infoHash}`);
    assert.ok(Number.isSafeInteger(r.seeds)&&r.sizeBytes>0&&Number.isFinite(Date.parse(r.uploadedAt)));
  }
});
test('RSS feeds: BT4G seeds unknown, Nyaa has actual count',()=>{
  const b=parseBT4GRSS(bt4g);assert.ok(b.length>0&&b.every(r=>r.seeds===null&&r.sizeBytes>0));
  const n=parseNyaaRSS(nyaa);assert.equal(n[0].seeds,12);
});
test('bad or cross-hash metadata cannot become playable',()=>{
  assert.throws(()=>parseKnaben({...knaben,hits:[{...knaben.hits[0],seeders:null}]}));
  assert.throws(()=>parseKnaben({...knaben,hits:[{...knaben.hits[0],magnetUrl:magnet(hash2)}]}));
  assert.throws(()=>parseEZTV({...eztv,torrents:[{...eztv.torrents[0],hash:'123'}]}));
  assert.throws(()=>parseApibay([{...apibay[0],size:'NaN'}]));
  assert.throws(()=>parseBitsearch({...bitsearch,results:[{...bitsearch.results[0],seeders:null}]}));
  assert.throws(()=>parseMagnetz({...magnetz,data:[{...magnetz.data[0],magnet_link:magnet(hash2)}]}));
  assert.throws(()=>parseBT4GRSS(bt4g.replace('2.72GB','garbage')));
});
test('provider failure stays isolated, relevance and sort are deterministic',()=>{
  const x=cli({query:'Ubuntu Linux ISO',providers:{apibay,knaben,eztv},failures:{bitsearch:'http_or_network'}});
  assert.equal(x.providers.bitsearch.status,'unavailable');assert.equal(x.providers.knaben.status,'ok');
  assert.equal(x.providers.eztv.status,'ok');assert.equal(x.results.length,1);
  const unrelated=cli({query:'Ubuntu Linux ISO',providers:{knaben:{...knaben,hits:[{...knaben.hits[0],title:'Other Linux ISO'}]}}});
  assert.equal(unrelated.results.length,0);
  assert.equal(mergeAndSort([parseKnaben(knaben),parseBitsearch(bitsearch)],'seeds',true).length,2);
  const sample=[{title:'Zeta',source:'nyaa',infoHash:'a',seeds:4},{title:'Alpha',source:'apibay',infoHash:'b',seeds:2}];
  assert.deepEqual(mergeAndSort([sample],'title',false).map(x=>x.title),['Alpha','Zeta']);
  assert.deepEqual(mergeAndSort([sample],'title',true).map(x=>x.title),['Zeta','Alpha']);
  assert.deepEqual(mergeAndSort([sample],'source',false).map(x=>x.source),['apibay','nyaa']);
  assert.deepEqual(mergeAndSort([sample],'source',true).map(x=>x.source),['nyaa','apibay']);
});
