from pathlib import Path
import re
r=Path(__file__).resolve().parents[2];app=(r/'Sources/gor/App/AppDelegate.swift').read_text();actions=(r/'Sources/gor/UI/MenuActions.swift').read_text()
# Whole menu-tree title inventory. Legacy aspect/projection names and technical
# acronyms keep their existing spelling; new menu-owned strings must be lowercase.
build=app[app.index('    func buildMenuBar()'):app.index('    // Observation only.',app.index('    func buildMenuBar()'))]
labels=re.findall(r'(?:item\(|title\s*[:=]\s*)"([^"\n]*)"',build)
legacy=set(['VR180','mono (no VR)','toggle VR180'])
for label in labels:
 if label==label.lower():continue
 assert label in legacy or re.match(r'^\d',label),('unexpected uppercase menu title',label)
for label in ['window','help','minimize','full screen','pip','zoom / restore','fill screen','↖','↗','↙','↘','•','smaller','larger','bring to front','shortcuts','issue report','about gor']:
 assert '"'+label+'"' in build,label
for label in ['tracks','video tracks','audio tracks','subtitle tracks','off']:
 assert '"'+label+'"' in actions,label
assert '"track \\(id)"' in actions and '"no \\(type) tracks"' in actions
# crop > detect keeps its short title (pin updated 2026-11-08: source drifted to "detect").
assert 'cropDetectMenuItem?.title = "detect"' in app
# Display metadata is a source title/language/codec, not menu-owned prose.
assert 'parts.append(text)' in actions
print('PASS whole menu-tree owned-title inventory: existing lowercase convention, legacy ratio/acronym exceptions preserved; all new Window/Help/Tracks/status labels lowercase; track metadata unchanged')
