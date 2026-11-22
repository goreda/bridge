#!/usr/bin/env python3
"""Exact current process-exit ownership policy. Not a native film-open claim."""
from pathlib import Path
import os,subprocess,tempfile,sys
r=Path(__file__).resolve().parents[2];s=(r/'Sources/gor/Engine/MPVCommand.swift').read_text()
a=s.index('enum PlayerProcessExitPolicy {');b=s.index('enum PlayerBackendAdmission:',a);fixed=s[a:b]
app=(r/'Sources/gor/App/AppDelegate.swift').read_text()
retire=app[app.index('    private func retireMPVForEmbedded()'):app.index('    private func closeEmbeddedForMPV()')]
assert retire.index('mpvProcess=nil')<retire.index('kill(process.processIdentifier,SIGTERM)')
assert 'PlayerProcessExitPolicy.shouldTerminate(current:self.mpvProcess,exited:exited,' in app
variants=[('fixed',fixed),('baseline-unconditional',fixed.replace('!quitting && current === exited','!quitting')),('mutant-nil-owner-quits',fixed.replace('!quitting && current === exited','!quitting && (current == nil || current === exited)')),('mutant-no-quitting-fence',fixed.replace('!quitting && current === exited','current === exited'))]
if '--wiring-only' in sys.argv:
 print('PASS retired ownership revoked before signal; queued exit calls current identity policy; native Swift NOT_RUN');raise SystemExit(0)
main='''import Foundation
let retired=Process(),replacement=Process()
precondition(PlayerProcessExitPolicy.shouldTerminate(current:retired,exited:retired,quitting:false))
precondition(!PlayerProcessExitPolicy.shouldTerminate(current:nil,exited:retired,quitting:false))
precondition(!PlayerProcessExitPolicy.shouldTerminate(current:replacement,exited:retired,quitting:false))
precondition(!PlayerProcessExitPolicy.shouldTerminate(current:retired,exited:retired,quitting:true))
print("PASS current-owned exit only; retired gorav handoff and replacement and deliberate quit fenced")
'''
with tempfile.TemporaryDirectory(prefix='retired-player-') as td:
 t=Path(td);(t/'main.swift').write_text(main)
 for label,code in variants:
  (t/'Policy.swift').write_text('import Foundation\n'+code)
  for mode in ['-Onone','-O']:
   p=subprocess.run([os.environ.get('SWIFTC','swiftc'),mode,str(t/'Policy.swift'),str(t/'main.swift'),'-o',str(t/'probe')],capture_output=True,text=True)
   assert p.returncode==0,(label,p.stderr)
   p=subprocess.run([str(t/'probe')],capture_output=True,text=True,timeout=10)
   assert (p.returncode==0)==(label=='fixed'),(label,mode,p.stdout,p.stderr)
   print(label,mode,'GREEN' if p.returncode==0 else 'RED')
print('NOT_RUN owner film open, normal-window pixels or actual child termination lifecycle')
