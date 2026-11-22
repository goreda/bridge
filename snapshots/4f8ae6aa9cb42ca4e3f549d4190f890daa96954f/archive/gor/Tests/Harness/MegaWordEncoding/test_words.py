"""Synthetic word encoding port only. Never read or emit real MEGA secrets."""
from pathlib import Path
import base64,json,hashlib,struct,random
root=Path(__file__).resolve().parents[3];p=root/'Sources/gor/Media/CDPSession.swift';s=p.read_text();a=s[s.index('private static func megaNodeKeyString'):s.index('private func fetchMegaNodes')]
for t in ['rawK as? [Any], !words.isEmpty','signed = n.int32Value','let parsed = Int32(s)','UInt32(bitPattern: signed)','(unsigned >> 24) & 0xff','(unsigned >> 16) & 0xff','(unsigned >> 8) & 0xff','unsigned & 0xff','.base64EncodedString()','.replacingOccurrences(of: "=", with: "")']:assert t in a,t
# The model deliberately handles integer and decimal-string fixtures only.
# NSNumber Bool/float/overflow coercions are native Foundation open gates.
def encode(handle,words):
 if not isinstance(words,list) or not words:return None
 out=b''
 for word in words:
  if isinstance(word,bool) or not isinstance(word,(int,str)):return None
  try:v=int(word)
  except ValueError:return None
  if isinstance(word,str) and (not word or word.strip()!=word or any(c not in '+-0123456789' for c in word)):return None
  if not -2**31<=v<2**31:return None
  out+=struct.pack('>I',v&0xffffffff)
 return handle+':'+base64.urlsafe_b64encode(out).decode().rstrip('=')
controls=[]
for words in [[0],[1],[-1],[-2**31],[2**31-1],[0,1,-1,-2**31,2**31-1]]:
 result=encode('fixture',words);token=result.split(':')[1];decoded=base64.urlsafe_b64decode(token+'='*((-len(token))%4));assert decoded==b''.join(struct.pack('>i',w) for w in words);assert '=' not in token and '+' not in token and '/' not in token
controls.append('signed boundary big-endian/base64url roundtrip')
assert encode('fixture',['0','-1','2147483647'])==encode('fixture',[0,-1,2147483647]);controls.append('decimal string/integer fixture equivalence')
for words in [[],None,['bad'],[{}],['2147483648']]:assert encode('fixture',words) is None
controls.append('empty/invalid shape and out-of-range string rejected')
rng=random.Random(261002)
for _ in range(1000):
 words=[rng.randrange(-2**31,2**31) for _ in range(8)];token=encode('fixture',words).split(':')[1];assert struct.unpack('>8i',base64.urlsafe_b64decode(token+'='*((-len(token))%4)))==tuple(words)
controls.append('1000 seeded eight-word signed roundtrips')
findings=[]
assert encode('',[0]).startswith(':');findings.append({'case':'empty handle','observed':'formatter does not require nonempty handle','scope':'synthetic input, caller validation unverified'})
for length in [1,3,9]:assert encode('fixture',[0]*length) is not None
findings.append({'case':'arbitrary nonzero word count','observed':'no expected format/key word-count gate in helper','scope':'provider-specific intended key sizes not validated; not cryptographic failure claim'})
print(json.dumps({'result':'PASS synthetic encoding controls and shape characterizations','controls':controls,'characterizations':findings,'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'open':['Foundation NSNumber Bool/float/overflow bridging','provider key format/length and caller handle validation','native base64/string parity, relay/provider decryption'],'scope':'Invented fixture words only, Python packing port/current Swift guards; no real secrets/provider/decryption/Swift execution'},indent=2))
