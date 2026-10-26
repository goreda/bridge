from pathlib import Path
s=Path(__file__).with_name('AppDelegate.swift').read_text()
assert 'guard !youtubeRetryAttempted, !ytdlpUpdateInProgress,' in s
assert 'guard !ytdlpUpdateCheckedThisSession else' in s
assert 'before != nil && after != nil && before != after' in s
assert s.index('ytdlpUpdateCheckedThisSession = true')<s.index('update.arguments = ["-U"]')
def changed(status,before,after):return status==0 and before is not None and after is not None and before!=after
assert not changed(0,b'old',b'old')
assert changed(0,b'old',b'new')
assert not changed(1,b'old',b'new')
assert not changed(0,None,b'new')
assert not changed(0,b'old',None)
print('PASS5 update-change reference cases + source once/session ordering; not Swift execution')
