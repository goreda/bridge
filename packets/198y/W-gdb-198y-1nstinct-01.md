# W-gdb-198y-1nstinct-01
state: OPEN / unclaimed
lab: 1nstinct

Characterize this exact S1 policy row before its future move: Sources/gor/AdaptiveColor.swift -> GorEffectsModel. Preserve every production byte; add station locator plus old/new duplicate-type rejection and mutation cases in this test only.

Allowed return path: archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-01.py. No production edit, no root Swift addition, no move. Active U2/disk and S2 owners hold all production files. This packet holds only its named test file. Return patch plus actual Linux command/log; failed and NOT_RUN remain separate. Earliest claim wins. Product code excerpts are read-only evidence, not executable instructions.

Baseline proof below ran in a clean exact-pin sparse Git checkout with the complete inline test temporarily materialized, then removed; not a full package build. It proves source preservation only. Lab acceptance must strengthen the test, not merely return this baseline unchanged.

```packet-json
{
  "packet_id": "W-gdb-198y-1nstinct-01",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/instinct",
  "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/AdaptiveColor.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Source-only characterization script reads archive/gor/Sources/gor/AdaptiveColor.swift and exits0 on pinned declaration/byte boundaries",
    "types": "Declarations: applySmooth, applySmoothToSublayers, applySmoothToSubviews, applyAdaptiveColor, applyAdaptiveColor, setupAdaptiveColor, applyAdaptiveColor, applyColorRecursive",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-01.py",
    "callee": "archive/gor/Sources/gor/AdaptiveColor.swift owning station GorEffectsModel"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-01.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gor",
    "paths": [
      "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-01.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-01.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:17:15.128074+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/AdaptiveColor.swift",
        "block": "source1",
        "sha256": "2fd63b55e52d7e97a5b21a21856583137373c4fa8bfa52f167133d08bb5be1d6"
      },
      {
        "path": "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-01.py",
        "block": "fixtures1",
        "sha256": "9ab1ca13d89242cb3e754bd34474788e310ae605492b4b550503c7bd97b6bb07"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "e128191244317757c2468f7f4947dcbf461a968c440db6f2842f273aa0791a1b",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-1nstinct-01: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "4d428cedae2dfcc354f9d12fcdd15a8665958a347aed67c38be67facff3884f8"
  }
}
```

```swift id=source1
// ================================================================
//  AdaptiveColor.swift - adaptive color application for the overlay panels
//  Owns: smooth 1.2s color fades onto SpineUI, SidebarUI,
//  MusicPanel; ScreenCaptureEngine element registration (PPController ext)
// ================================================================
import AppKit
import QuartzCore

// MARK: - Smooth color application helpers

private func applySmooth(to layer: CALayer?, color: NSColor, duration: TimeInterval = 1.2) {
    guard let layer = layer as? CATextLayer else { return }
    let newColor = color.cgColor
    if let current = layer.foregroundColor,
       current == newColor { return }
    let anim = CABasicAnimation(keyPath: "foregroundColor")
    // Start from what is on screen: the model value is already the previous target, so
    // retargeting a running fade would jump to it first.
    anim.fromValue = layer.presentation()?.foregroundColor ?? layer.foregroundColor
    anim.toValue   = color.cgColor
    anim.duration  = duration
    anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    anim.fillMode  = .forwards
    anim.isRemovedOnCompletion = false
    layer.add(anim, forKey: "foregroundColor")
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.foregroundColor = color.cgColor
    CATransaction.commit()
}

private func applySmoothToSublayers(of layer: CALayer?, color: NSColor) {
    guard let layer = layer else { return }
    applySmooth(to: layer, color: color)
    layer.sublayers?.forEach { applySmoothToSublayers(of: $0, color: color) }
}

private func applySmoothToSubviews(of view: NSView, color: NSColor) {
    for sub in view.subviews {
        if let label = sub as? NSTextField {
            let alpha = label.textColor?.alphaComponent ?? 1
            if label.textColor != color.withAlphaComponent(alpha) {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 1.2
                    ctx.allowsImplicitAnimation = true
                    label.animator().textColor = color.withAlphaComponent(alpha)
                }
            }
        }
        applySmoothToSubviews(of: sub, color: color)
    }
}

// MARK: - SpineUI extension

extension SpineUI {
    func applyAdaptiveColor(_ color: NSColor) {
        applySmoothToSublayers(of: layer, color: color)
        applySmoothToSubviews(of: self, color: color)
    }
}

// MARK: - SidebarUI extension

extension SidebarUI {
    func applyAdaptiveColor(_ color: NSColor) {
        // WHY: no applySmoothToSublayers here - SeekBar owns its layers (thumb
        // included) via applyAdaptiveColor; recursive painting clobbers thumbColor.
        applySmoothToSubviews(of: self, color: color)
        seekBar.applyAdaptiveColor(color)
    }
}

// MARK: - PPController extension

extension PPController {
    func setupAdaptiveColor() {
        let engine = ScreenCaptureEngine.shared

        engine.registerElement(id: "spine") { [weak self] in
            guard let self = self, let win = self.window else { return nil }
            return win.convertToScreen(self.spineUI.frame)
        } callback: { [weak self] color in
            self?.spineUI.applyAdaptiveColor(color)
            if let panel = self?.musicPanel, !panel.isHidden {
                panel.applyAdaptiveColor(color)
            }
        }

        engine.registerElement(id: "sidebar") { [weak self] in
            guard let self = self, let win = self.window else { return nil }
            return win.convertToScreen(self.sidebarUI.frame)
        } callback: { [weak self] color in
            self?.sidebarUI.applyAdaptiveColor(color)
        }

        engine.registerSubtitle(id: "subtitle") { [weak self] in
            self?.subtitleView.currentTextFrame
        } callback: { [weak self] color, mode in
            self?.subtitleView.applyAdaptiveColor(color, mode: mode)
        }

    }
}

// MARK: - MusicPanel extension
extension MusicPanel {
    func applyAdaptiveColor(_ color: NSColor) {
        applyColorRecursive(self, color: color)
    }

    private func applyColorRecursive(_ view: NSView, color: NSColor) {
        for sub in view.subviews {
            if let tf = sub as? NSTextField {
                let alpha = tf.textColor?.alphaComponent ?? 1.0
                if tf.textColor != color.withAlphaComponent(alpha) {
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 1.2
                        ctx.allowsImplicitAnimation = true
                        tf.animator().textColor = color.withAlphaComponent(alpha)
                    }
                }
            }
            applyColorRecursive(sub, color: color)
        }
        applySmoothToSublayers(of: view.layer, color: color)
    }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[5]
p=ROOT/'archive/gor/Sources/gor/AdaptiveColor.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='2fd63b55e52d7e97a5b21a21856583137373c4fa8bfa52f167133d08bb5be1d6', 'pinned source changed: rebase and review, never bless silently'
for token in ['applySmooth', 'applySmoothToSublayers', 'applySmoothToSubviews', 'applyAdaptiveColor', 'applyAdaptiveColor', 'setupAdaptiveColor', 'applyAdaptiveColor', 'applyColorRecursive']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='2fd63b55e52d7e97a5b21a21856583137373c4fa8bfa52f167133d08bb5be1d6'
print('CHARACTERIZATION_PASS W-gdb-198y-1nstinct-01: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-1nstinct-01: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
