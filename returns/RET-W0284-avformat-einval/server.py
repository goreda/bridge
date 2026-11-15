#!/usr/bin/env python3
"""Local synthetic HLS origin. Paths: /vod/*, /live/*, /flaky/* ; media from ./media (generated). Logs to server.log."""
import http.server, socketserver, os, sys, threading
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "media")
BW = {"low": 200000, "mid": 550000, "hi": 1100000}
RES = {"low": "160x90", "mid": "320x180", "hi": "640x360"}
LOCK = threading.Lock(); STATE = {"polls": 0, "truncated": False}
LOG = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "server.log"), "a", buffering=1)
def master():
    s = "#EXTM3U\n"
    for v in ("low", "mid", "hi"):
        s += f'#EXT-X-STREAM-INF:BANDWIDTH={BW[v]},RESOLUTION={RES[v]},CODECS="avc1.42c01e,mp4a.40.2"\n{v}.m3u8\n'
    return s
def live_playlist(v):
    with LOCK: STATE["polls"] += 1; n = STATE["polls"]
    first = n  # window slides one segment per poll
    last = first + 3
    s = f"#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:{first}\n"
    if first + 0 > 5: s += "#EXT-X-DISCONTINUITY-SEQUENCE:1\n"
    for q in range(first, last + 1):
        if q == 5: s += "#EXT-X-DISCONTINUITY\n"
        s += f"#EXTINF:2.000,\nseg_{v}_{q}.ts\n"
    if first >= 8: s = s.rstrip("\n") + "\n#EXT-X-ENDLIST\n"
    return s
class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, f, *a): LOG.write(self.path + " " + (f % a) + "\n")
    def send(self, body, ctype, cut=None):
        self.send_response(200); self.send_header("Content-Type", ctype); self.send_header("Content-Length", str(len(body)))
        self.end_headers(); self.wfile.write(body if cut is None else body[:cut]); self.wfile.flush()
        if cut is not None: self.close_connection = True; self.connection.shutdown(2)
    def do_GET(self):
        p = self.path.split("?")[0].strip("/").split("/"); mode, name = p[0], p[-1]
        M = "application/vnd.apple.mpegurl"
        if name == "master.m3u8": return self.send(master().encode(), M)
        if name.endswith(".m3u8"):
            v = name[:-5]
            if mode == "live": return self.send(live_playlist(v).encode(), M)
            return self.send(open(os.path.join(ROOT, name), "rb").read(), M)
        if name.endswith(".ts"):
            if name.startswith("seg_"):  # seg_<v>_<q>.ts -> media file <v>_<q%8>.ts
                _, v, q = name[:-3].split("_"); f = f"{v}_{int(q) % 8}.ts"
            else: f = name
            data = open(os.path.join(ROOT, f), "rb").read()
            if mode == "flaky" and f == "hi_2.ts":
                with LOCK: first = not STATE["truncated"]; STATE["truncated"] = True
                if first: LOG.write("INJECT truncate " + f + "\n"); return self.send(data, "video/mp2t", cut=len(data) // 2)
            return self.send(data, "video/mp2t")
        self.send_error(404)
class S(socketserver.ThreadingMixIn, http.server.HTTPServer): daemon_threads = True; allow_reuse_address = True
if __name__ == "__main__": S(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
