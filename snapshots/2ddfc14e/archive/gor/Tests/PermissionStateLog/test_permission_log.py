#!/usr/bin/env python3
"""V1.3 contract: launch permission log is passive (never prompts) and wired into main.swift. Source-level, Linux; not native proof."""

# Core pure-move source view; existing assertions and compiler bodies are unchanged.
import importlib.util as _core_iu
from pathlib import Path as _CorePath
_core_root=next(p for p in _CorePath(__file__).resolve().parents if (p/'Tests/Structure/core_source.py').is_file())
_core_spec=_core_iu.spec_from_file_location('core_source_view',_core_root/'Tests/Structure/core_source.py')
_core_view=_core_iu.module_from_spec(_core_spec);_core_spec.loader.exec_module(_core_view)
_core_read=_core_view.read_source
_core_bytes=_core_view.read_bytes
_core_materialize=_core_view.materialize
import re, unittest, pathlib
R = pathlib.Path(__file__).resolve().parents[2] / "Sources/gor"
SRC = _core_read(R / "GORResources.swift")
BODY = SRC[SRC.index("enum PermissionStateLog"):]
class T(unittest.TestCase):
    def test_no_prompting_apis(self):
        for bad in ["CGRequestScreenCaptureAccess", "requestAccess", "AXIsProcessTrustedWithOptions", "SCShareableContent", "AVAudioEngine", "CATapDescription"]:
            self.assertNotIn(bad, BODY)
    def test_uses_preflight_apis_only(self):
        for ok in ["CGPreflightScreenCaptureAccess()", "AVCaptureDevice.authorizationStatus(for: .video)", "AXIsProcessTrusted()"]:
            self.assertIn(ok, BODY)
    def test_four_named_states_incl_tap_unavailable(self):
        self.assertEqual(re.findall(r'\("(\w+)", ', BODY.split("static func logLaunch")[0]), ["screen_recording", "camera", "accessibility", "system_audio_tap"])
        self.assertIn("unavailable-no-public-preflight", BODY)
    def test_log_line_has_no_user_data(self):
        m = re.search(r'NSLog\("([^"]*)"', BODY)
        self.assertEqual(m.group(1), "[GORPermission] permission=%@ state=%@ macos=%@")
    def test_called_once_from_main(self):
        main = _core_read(R / "main.swift")
        self.assertEqual(main.count("PermissionStateLog.logLaunch()"), 1)
        i = main.index("PermissionStateLog.logLaunch()")
        self.assertGreater(i, main.index('"--bootcheck"'))  # bootcheck exits before any logging/UI
        self.assertLess(i, main.index("app.run()"))
if __name__ == "__main__":
    unittest.main()
