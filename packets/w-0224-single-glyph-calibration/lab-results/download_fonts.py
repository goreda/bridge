import argparse,hashlib,json,pathlib,urllib.request
R=pathlib.Path(__file__).parent
p=argparse.ArgumentParser();p.add_argument('--cache',type=pathlib.Path,required=True);a=p.parse_args()
for f in json.loads((R/'font-manifest.json').read_text())['fonts']:
 for name,url,digest in [(f['file_name'],f['upstream_url'],f['sha256']),('OFL.txt',f['ofl_url'],f['ofl_sha256'])]:
  b=urllib.request.urlopen(url).read()
  if hashlib.sha256(b).hexdigest()!=digest:raise ValueError('HashMismatch:'+f['family']+':'+name)
  if name=='OFL.txt' and b'SIL OPEN FONT LICENSE Version 1.1' not in b:raise ValueError('LicenceMismatch')
  dest=a.cache/f['slug']/name;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(b)
 print(f['family'],'verified download only')
