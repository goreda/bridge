#!/usr/bin/env python3
"""Gofile contents handler must ignore the CORS preflight and a failed body read.

The rewritten gofile.io frontend sends an empty-header OPTIONS preflight with the same
URL as the real GET. Treating it as the listing made getResponseBody fail, finish([])
fell back to the legacy DOM route, and the stream hung on "intercepting signed URL...".
"""
import re, sys, unittest, pathlib
SRC = (pathlib.Path(__file__).resolve().parents[2] / "Sources/gor/Media/CDPSession.swift").read_text()
START = SRC.index("func resolveGofileFilesCDP")
BODY = SRC[START:SRC.index("resolveGofileFilesDOMLegacy(contentId: String", START)]

class T(unittest.TestCase):
    def test_request_ignores_preflight(self):
        h = BODY[BODY.index('"Network.requestWillBeSent"] ='):BODY.index('"Network.responseReceived"] =')]
        self.assertIn('"Preflight"', h)
        self.assertIn('uppercased() == "GET"', h)
        self.assertLess(h.index('"Preflight"'), h.index("requests.insert(id)"))
    def test_response_requires_tracked_request(self):
        h = BODY[BODY.index('"Network.responseReceived"] ='):BODY.index('"Network.loadingFinished"] =')]
        self.assertIn("requests.contains(id)", h)
    def test_failed_body_read_not_terminal(self):
        p = BODY[BODY.index("func parseResponse"):BODY.index("func readBody")]
        m = re.search(r'guard !primaryDone[^\n]*response\["result"\] != nil else \{ return \}', p)
        self.assertIsNotNone(m)
        self.assertNotIn("finish(", m.group(0))
if __name__ == "__main__":
    unittest.main()
