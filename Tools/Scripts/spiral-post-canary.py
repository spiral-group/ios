# Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
#
# Canary listener for the post-sandbox attack corpus. Binds 127.0.0.1 by
# default; the device pass binds the Mac's LAN address instead (a phone cannot
# reach the Mac's loopback): pass it as the second argument.
#
#   47913/tcp  plain listener: every accepted connection is a hit; the first
#              line (an HTTP request line, a WebSocket upgrade) is logged and a
#              tiny HTTP 200 goes back, so a fetch that got through completes.
#   47915/tcp  "https" listener: never speaks TLS, only counts the connect, so
#              an https:// or wss:// attempt that reached the wire shows up.
#   47913/udp  STUN / anything datagram (WebRTC ICE, a QUIC attempt).
#   47914/tcp  control (NOT a canary): GET /stats, GET /reset, POST /results.
#
# Usage: python3 -I Tools/Scripts/spiral-post-canary.py <out-dir> [bind-address]

import json
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
HOST = sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1"
hits = []
lock = threading.Lock()


def record(kind, port, first_line):
    with lock:
        hits.append({"t": time.time(), "kind": kind, "port": port, "line": first_line[:300]})
    with open(f"{OUT}/canary-hits.log", "a") as log:
        log.write(f"{time.strftime('%H:%M:%S')} {kind}:{port} {first_line[:300]!r}\n")


def serve_tcp(port, speaks_http):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((HOST, port))
    server.listen(64)
    while True:
        conn, peer = server.accept()
        threading.Thread(target=handle_tcp, args=(conn, port, speaks_http, peer[0]), daemon=True).start()


def handle_tcp(conn, port, speaks_http, peer):
    conn.settimeout(1.5)
    first = b""
    try:
        first = conn.recv(4096)
    except OSError:
        pass
    line = first.split(b"\r\n", 1)[0].decode("latin-1", "replace") if first else "<connect, no bytes>"
    if not speaks_http and first:
        line = f"<tls/raw {len(first)} bytes>"
    record("tcp", port, f"{line} [from {peer}]")
    if speaks_http and first:
        body = b"canary"
        try:
            conn.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nAccess-Control-Allow-Origin: *\r\n"
                         b"Content-Length: " + str(len(body)).encode() + b"\r\nConnection: close\r\n\r\n" + body)
        except OSError:
            pass
    conn.close()


def serve_udp(port):
    server = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    server.bind((HOST, port))
    while True:
        data, peer = server.recvfrom(4096)
        record("udp", port, f"<{len(data)} bytes, first {data[:4].hex()}> [from {peer[0]}]")


def sample_cpu():
    # Simulator WebContent processes are ordinary Mac processes; their CPU is
    # what a spinning post costs. Only the simulator's, not Safari's.
    import subprocess
    while True:
        try:
            out = subprocess.run(["ps", "-A", "-o", "pid=,pcpu=,rss=,command="], capture_output=True, text=True).stdout
            rows = [l.split(None, 3) for l in out.splitlines() if "WebKit.WebContent" in l and ("CoreSimulator" in l or "RuntimeRoot" in l or "iOS" in l)]
            with open(f"{OUT}/cpu.log", "a") as log:
                log.write(f"{time.time():.1f} " + " ".join(f"{r[0]}:{r[1]}%:{int(r[2])//1024}MB" for r in rows) + "\n")
        except Exception as error:
            pass
        time.sleep(1)


class Control(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, payload):
        data = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path.startswith("/stats"):
            with lock:
                self.reply({"total": len(hits), "hits": hits})
        elif self.path.startswith("/mark"):
            with open(f"{OUT}/cpu.log", "a") as log:
                log.write(f"{time.time():.1f} MARK {self.path[6:]}\n")
            self.reply({"ok": True})
        elif self.path.startswith("/reset"):
            with lock:
                hits.clear()
            self.reply({"ok": True})
        else:
            self.reply({"error": "unknown"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        name = self.path.strip("/").replace("/", "-") or "results"
        with open(f"{OUT}/{name}.json", "wb") as f:
            f.write(body)
        self.reply({"ok": True, "bytes": len(body)})


if __name__ == "__main__":
    threading.Thread(target=serve_tcp, args=(47913, True), daemon=True).start()
    threading.Thread(target=serve_tcp, args=(47915, False), daemon=True).start()
    threading.Thread(target=serve_udp, args=(47913,), daemon=True).start()
    threading.Thread(target=sample_cpu, daemon=True).start()
    print(f"canary listening on {HOST}:47913/tcp+udp, 47915/tcp; control 47914", flush=True)
    ThreadingHTTPServer((HOST, 47914), Control).serve_forever()
