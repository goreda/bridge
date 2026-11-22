#!/usr/bin/env python3
"""Portable source contract checks; not an AppKit runtime or pixel test."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
S = (ROOT/'Sources/GorAVMetalPresenter/core/MetalPresenter.swift').read_text()
V = S[S.index('public final class MetalPresenterView:'):S.index('/// FrameSink conformance')]
class GeometryContract(unittest.TestCase):
    def test_layout_and_backing_and_attachment_share_geometry_sync(self):
        for event in ('layout()', 'viewDidChangeBackingProperties()', 'viewDidMoveToWindow()'):
            body = V.split('func '+event, 1)[1].split('\n    }',1)[0]
            self.assertIn('synchronizeDrawableGeometry()', body)
    def test_zero_nonfinite_geometry_refused_before_callback(self):
        helper = V.split('private func synchronizeDrawableGeometry()',1)[1]
        self.assertIn('size.width.isFinite', helper)
        self.assertIn('size.height.isFinite', helper)
        self.assertLess(helper.index('size.width > 0'), helper.index('onResize?'))
        self.assertNotIn('ml.drawableSize = .zero', helper)
    def test_no_new_window_or_host_teardown_in_view(self):
        self.assertNotIn('NSWindow(', V)
        self.assertNotIn('removeFromSuperview', V)
        self.assertNotIn('2.0', V)
    def test_existing_presenter_embedding_and_detach_preserved(self):
        self.assertIn('hostView.addSubview(v)', S)
        self.assertIn('self.window = nil', S)
        self.assertIn('view.removeFromSuperview()', S)
        self.assertIn('guard window == nil else', S)
if __name__ == '__main__': unittest.main()
