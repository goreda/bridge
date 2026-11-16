#!/usr/bin/env python3
# Non-secret public test vector key: bytes00..17. NOT a service/file credential.
# Independent batch oracle for documented transfer.it plaintext chunk/metaMAC.
import json,hashlib
from cryptography.hazmat.primitives.ciphers import Cipher,algorithms,modes

def filekey(data):
    key=bytes(range(16));nonce=bytes(range(16,24));iv=nonce*2
    offset=0;size=131072;macs=[]
    while offset<len(data):
        part=data[offset:offset+size];offset+=len(part);size=min(1048576,size+131072)
        padded=part+bytes((-len(part))%16)
        cipher=Cipher(algorithms.AES(key),modes.CBC(iv)).encryptor()
        encrypted=cipher.update(padded)+cipher.finalize();macs.append(encrypted[-16:])
    if macs:
        cipher=Cipher(algorithms.AES(key),modes.CBC(bytes(16))).encryptor()
        folded=(cipher.update(b''.join(macs))+cipher.finalize())[-16:]
        words=[int.from_bytes(folded[i:i+4],'big') for i in range(0,16,4)]
        meta=(words[0]^words[1]).to_bytes(4,'big')+(words[2]^words[3]).to_bytes(4,'big')
    else:meta=bytes(8)
    tail=nonce+meta
    return bytes(a^b for a,b in zip(key,tail))+tail

if __name__=='__main__':
    cases=[]
    for size in [0,1,15,16,17,131056,131057,131071,131072,131073,176444,393216,393217,1048577,5767169]:
        data=bytes((i*97)%251 for i in range(size))
        cases.append(dict(size=size,sha256=hashlib.sha256(data).hexdigest(),fileKeyHex=filekey(data).hex()))
    import struct,wave,io
    raw=b''.join(struct.pack('<hh',((i*97)%60001)-30000,((i*193)%60001)-30000) for i in range(44100))
    wav=io.BytesIO()
    with wave.open(wav,'wb') as out:
        out.setnchannels(2);out.setsampwidth(2);out.setframerate(44100);out.writeframes(raw)
    data=wav.getvalue()
    anchor=dict(size=len(data),sha256=hashlib.sha256(data).hexdigest(),fileKeyHex=filekey(data).hex())
    print(json.dumps({'scope':'synthetic non-secret keys; documented Go/transfer protocol oracle, not service vectors','vectors':cases,'wavAnchor':anchor},indent=2))
