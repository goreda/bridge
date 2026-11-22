#!/usr/bin/env python3
"""Records edits made to the S4a moved files (Viewport.swift, CropDetector.swift) after the pure move.
Usage: viewport_s4a_record.py ROOT BLOB_DIR [--residual]
  ROOT is the tree with the live files; BLOB_DIR holds the base blobs as <old file name> (GorFit.swift, PPController.swift).
Historical fields (base, old, new, start, end, prefix, sha256, residual_*) are never written. Per move it writes
base_blob_sha256, current_sha256 and, when the live file is not the pure move, edit.hunks (line spans plus replacement hashes).
It refuses when a base blob does not rebuild the pinned pure-move bytes. Run viewport_s4a_preservation_test.py afterwards."""
import json,sys,os
from pathlib import Path
here=Path(__file__).resolve().parent
sys.path.insert(0,str(here))
import viewport_s4a_preservation_test as t
def main(root,blobs,residual=False):
    root,blobs=Path(root),Path(blobs)
    mp=root/'Tests/Architecture/viewport-s4a-map.json';spec=json.loads(mp.read_text())
    for m in spec['moves']:
        text=(blobs/m['old']).read_text();m['base_blob_sha256']=t.sha(text)
        if 'start' in m:
            a=text.index(m['start']);b=text.index(m['end'],a);body=text[a:b]
            assert t.sha(body)==m['sha256'],('base blob does not hold the pinned body',m['old'])
            hist=m['prefix']+body
        else:
            assert t.sha(text)==m['sha256'],('base blob does not match the pinned file',m['old'])
            hist=text
        live=(root/'Sources/gor'/m['new']).read_text()
        if residual and 'start' in m:
            ra=text.index(m['residual_start']);rb=text.index(m['residual_end'],ra);exp=text[:ra]+text[rb:]
            cur=t._pp_split().path(root,'PPController.swift').read_text()
            m['residual_current_sha256']=t.sha(cur);m.pop('residual_edit',None)
            if cur!=exp:m['residual_edit']={'hunks':t.make_edit(exp,cur)}
            t.check_current(exp,cur,m,'residual','residual_current_sha256','residual_edit')
            m['residual_note']='INHERITED, UNREVIEWED pre-existing PP drift (%d hunks, identical at 4d8ba0c6); pinned only so crop edits are not blamed for it. Debt, not a waiver: pending independent review.'%len(m.get('residual_edit',{}).get('hunks',[]))
        m['current_sha256']=t.sha(live);m.pop('edit',None)
        if live!=hist:m['edit']={'hunks':t.make_edit(hist,live)}
        t.check_current(hist,live,m,m['new'])
        print(m['new'],'edited' if 'edit' in m else 'pure move',len(m.get('edit',{}).get('hunks',[])),'hunks',m['current_sha256'][:8])
    mp.write_text(json.dumps(spec,indent=1)+'\n')
if __name__=='__main__':main(sys.argv[1],sys.argv[2],'--residual' in sys.argv[3:])
