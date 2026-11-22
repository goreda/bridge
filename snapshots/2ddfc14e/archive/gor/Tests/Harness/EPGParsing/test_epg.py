"""XMLTV delegate state port driven by Python Expat, not Foundation XMLParser."""
from pathlib import Path
from datetime import datetime,timezone
import json,hashlib,xml.parsers.expat
root=Path(__file__).resolve().parents[3];p=root/'Sources/gor/Media/IPTV.swift';s=p.read_text();a=s[s.index('private final class EPGXMLParser'):s.index('// MARK: - QualityHitView')]
for t in ['f.dateFormat = "yyyyMMddHHmmss Z"','parser.parse()','result[key]?.sort { $0.start < $1.start }','curChannel  = (attrs["channel"] ?? "").lowercased()','textBuf += string','let start = curStart, let stop = curStop','result[curChannel, default: []].append(prog)']:assert t in a,t
assert 'stop > start' not in a and 'guard parser.parse()' not in a
assert 'return progs.first { $0.start <= now && now < $0.stop }' in s
def date(v):
 try:return datetime.strptime(v,'%Y%m%d%H%M%S %z')
 except (ValueError,TypeError):return None
class Parser:
 def __init__(self):self.rows={};self.inside=False;self.capture=False;self.buf='';self.title='';self.error=False
 def start(self,el,attrs):
  if el=='programme':self.inside=True;self.channel=attrs.get('channel','').lower();self.begin=date(attrs.get('start'));self.stop=date(attrs.get('stop'));self.title='';self.capture=False;self.buf=''
  elif el=='title' and self.inside:self.capture=True;self.buf=''
  else:self.capture=False
 def chars(self,text):
  if self.capture:self.buf+=text
 def end(self,el):
  if el=='title' and self.inside and self.capture:
   if self.buf.strip():self.title=self.buf.strip()
   self.capture=False
  elif el=='programme':
   if self.inside and self.channel and self.begin is not None and self.stop is not None:self.rows.setdefault(self.channel,[]).append({'title':self.title or '(placeholder)','start':self.begin,'stop':self.stop})
   self.inside=False;self.capture=False
  else:self.capture=False
 def parse(self,wire,step=None):
  parser=xml.parsers.expat.ParserCreate();parser.StartElementHandler=self.start;parser.EndElementHandler=self.end;parser.CharacterDataHandler=self.chars
  try:
   if step:
    for i in range(0,len(wire),step):parser.Parse(wire[i:i+step],False)
    parser.Parse(b'',True)
   else:parser.Parse(wire,True)
  except xml.parsers.expat.ExpatError:self.error=True
  for rows in self.rows.values():rows.sort(key=lambda r:r['start'])
  return self.rows
item='<programme channel="News.TR" start="20261002000000 +0300" stop="20261002010000 +0300"><title>Café &amp; News 😀</title></programme>'
wire=('<tv>'+item+'</tv>').encode();controls=[]
for step in range(1,len(wire)+1):
 x=Parser();rows=x.parse(wire,step);assert not x.error and rows['news.tr'][0]['title']=='Café & News 😀'
controls.append('XML character/entity/Unicode accumulation at every byte chunk size')
row=rows['news.tr'][0];assert row['start'].astimezone(timezone.utc).isoformat()=='2026-10-01T21:00:00+00:00';controls.append('explicit timezone conversion')
for instant,expected in [(row['start'],True),(row['stop'],False)]:assert (row['start']<=instant<row['stop'])==expected
controls.append('current-program start-inclusive stop-exclusive boundary')
x=Parser();assert not x.parse(b'<tv><programme channel="x" start="bad" stop="bad"><title>x</title></programme></tv>');controls.append('invalid dates skipped')
x=Parser();rows=x.parse(b'<tv><programme channel="x" start="20261002000000 +0000" stop="20261002010000 +0000"/></tv>');assert rows['x'][0]['title']=='(placeholder)';controls.append('missing title placeholder path')
x=Parser();rows=x.parse(('<tv>'+item.replace('20261002000000','20261002020000').replace('20261002010000','20261002030000')+item+'</tv>').encode());assert rows['news.tr'][0]['start']<rows['news.tr'][1]['start'];controls.append('records sorted by start')
reds=[]
x=Parser();rows=x.parse(('<tv>'+item+'<broken>').encode());assert x.error and len(rows['news.tr'])==1;reds.append({'case':'malformed tail after complete programme','observed':'partial records survive parse error','scope':'Expat-driven delegate port, Foundation partial-record behavior unverified'})
x=Parser();rows=x.parse(('<tv>'+item.replace('20261002010000','20261001230000')+'</tv>').encode());assert rows['news.tr'][0]['stop']<rows['news.tr'][0]['start'];reds.append({'case':'reversed interval','observed':'admitted though never current under interval predicate'})
x=Parser();rows=x.parse(('<tv>'+item.replace('<title>Café &amp; News 😀</title>','<title lang="en">English</title><title lang="tr">Turkish</title>')+'</tv>').encode());assert rows['news.tr'][0]['title']=='Turkish';reds.append({'case':'multiple title languages','observed':'last nonempty title wins regardless of language','scope':'policy characterization, preference unresolved'})
x=Parser();rows=x.parse(('<tv>'+item.replace('<title>Café &amp; News 😀</title>','<title>Before <b>nested</b> after</title>')+'</tv>').encode());assert rows['news.tr'][0]['title']=='(placeholder)';reds.append({'case':'nested title element','observed':'capture reset drops title','scope':'malformed/unexpected input characterization, XMLTV format acceptance not certified'})
print(json.dumps({'result':'PASS XML delegate controls and admission characterizations','controls':controls,'characterizations':reds,'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'open':['Foundation XMLParser/DateFormatter parity and entity settings','actual EPG cache/update/provider/fallback behavior','language preference and malformed-input policy','native UI guide/search timing'],'scope':'Current Swift guards + Python delegate port driven by Expat, no Swift/provider/network/UI execution'},indent=2))
