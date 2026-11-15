#!/usr/bin/env python3
"""Synthetic HTTP servers for W-0286 e2e checks. Deterministic content:
byte[i] = (i*131 + 17) & 0xff. No real endpoints involved.

Paths:
  /full     - range-capable (Accept-Ranges: bytes, 206, ETag)
  /drop     - range-capable; first non-range request dies after DROP_AT bytes
  /dribble  - range-capable, 4KB chunks every 20ms (slow relay)
  /norange  - ignores Range, always 200 full body (Accept-Ranges: none)
  /chunked  - ignores Range, Transfer-Encoding: chunked, no Content-Length
"""
import sys, time, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ETAG = '"synth-7f3a"'
LENGTHS = {"/full": 1 << 20, "/drop": 300000, "/dribble": 200000,
           "/norange": 150000, "/chunked": 120000, "/barelf": 50000}
DROP_AT = 200000
dropped_once = set()
lock = threading.Lock()

def gen(n):
    return bytes(((i * 131 + 17) & 0xFF) for i in range(n))

class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass

    def _range(self, length):
        r = self.headers.get("Range")
        if not r: return None
        try:
            spec = r.split("=", 1)[1]
            a, b = spec.split("-", 1)
            start = int(a)
            end = int(b) if b else length - 1
            end = min(end, length - 1)
            if start > end or start >= length: return "invalid"
            return start, end
        except Exception:
            return "invalid"

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path not in LENGTHS:
            self.send_error(404); return
        length = LENGTHS[path]
        rng = self._range(length)
        honor = path in ("/full", "/drop", "/dribble")
        if rng == "invalid" and honor:
            self.send_response(416)
            self.send_header("Content-Range", "bytes */%d" % length)
            self.send_header("Content-Length", "0")
            self.end_headers(); return

        if path == "/barelf":
            # LF-only response lines (no CR) - exercises tolerant line parsing
            body = gen(length)
            raw = ("HTTP/1.1 200 OK\nContent-Length: %d\nServer: synth-barelf\n\n" % length).encode() + body
            self.wfile.write(raw)
            self.close_connection = True
            return

        if path == "/chunked":
            self.send_response(200)
            self.send_header("Transfer-Encoding", "chunked")
            self.send_header("ETag", ETAG)
            self.end_headers()
            data = gen(length)
            for i in range(0, len(data), 8192):
                c = data[i:i+8192]
                self.wfile.write(("%x\r\n" % len(c)).encode() + c + b"\r\n")
            self.wfile.write(b"0\r\n\r\n")
            return

        if honor and rng:
            start, end = rng
            body = gen(length)[start:end + 1]  # slice of the SAME content
            self.send_response(206)
            self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, length))
        else:
            body = gen(length)
            self.send_response(200)
            self.send_header("Accept-Ranges", "none" if path == "/norange" else "bytes")
        self.send_header("ETag", ETAG)
        self.send_header("Last-Modified", "Wed, 11 Nov 2026 00:00:00 GMT")
        self.send_header("Server", "synth/1.0")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()

        full_body = rng is None or rng == (0, length - 1)
        if path == "/drop" and full_body:
            with lock:
                first = path not in dropped_once
                dropped_once.add(path)
            if first:
                self.wfile.write(body[:DROP_AT])
                self.wfile.flush()
                self.connection.shutdown(2)  # hard drop mid-body
                self.connection.close()
                return
        if path == "/dribble":
            for i in range(0, len(body), 4096):
                self.wfile.write(body[i:i+4096]); self.wfile.flush()
                time.sleep(0.02)
            return
        self.wfile.write(body)

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8971
    ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
