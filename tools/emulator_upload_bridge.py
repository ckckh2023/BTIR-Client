#!/usr/bin/env python3
"""Forward HarmonyOS emulator uploads through the Linux host's TLS stack.

The emulator reaches host loopback at 10.0.2.2. This service binds only to
127.0.0.1, accepts the two BTIR upload routes, and streams request bodies to
the configured production server without storing them on disk.
"""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import http.client
import json


HOST = "btir-online.ai-premol.cn"
PORT = 18766
MAX_BODY = 512 * 1024 * 1024
UPLOAD_PATHS = frozenset(("/tasks/3d", "/tasks/3d/archive"))


class UploadHandler(BaseHTTPRequestHandler):
    def log_message(self, format_string, *args):
        # File names, tokens, and request bodies must never appear in logs.
        pass

    def reply(self, status: int, body: bytes, content_type: str = "application/json"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)
        self.close_connection = True

    def do_GET(self):
        if self.path != "/healthz":
            self.reply(404, b"{}")
            return
        self.reply(200, b'{"service":"btir-emulator-upload-bridge"}')

    def do_POST(self):
        if self.path not in UPLOAD_PATHS:
            self.reply(404, b"{}")
            return
        if self.headers.get("Transfer-Encoding"):
            self.reply(400, b'{"detail":"Transfer-Encoding is not supported"}')
            return
        try:
            length = int(self.headers["Content-Length"])
        except (KeyError, TypeError, ValueError):
            self.reply(411, b'{"detail":"Content-Length is required"}')
            return
        if length < 0 or length > MAX_BODY:
            self.reply(413, b'{"detail":"Upload exceeds the server limit"}')
            return

        connection = http.client.HTTPSConnection(HOST, timeout=600)
        try:
            connection.putrequest("POST", self.path)
            connection.putheader("Content-Length", str(length))
            for name in ("Content-Type", "Authorization"):
                value = self.headers.get(name)
                if value:
                    connection.putheader(name, value)
            connection.endheaders()

            remaining = length
            while remaining:
                chunk = self.rfile.read(min(64 * 1024, remaining))
                if not chunk:
                    raise ConnectionError("Emulator disconnected before upload completed")
                connection.send(chunk)
                remaining -= len(chunk)

            response = connection.getresponse()
            body = response.read()
            content_type = response.getheader("Content-Type", "application/json")
            self.reply(response.status, body, content_type)
            print(f"Upload route {self.path}: {length} bytes, HTTP {response.status}", flush=True)
        except Exception as error:
            body = json.dumps({"detail": f"Upload bridge failed: {error}"}).encode()
            try:
                self.reply(502, body)
            except (BrokenPipeError, ConnectionResetError):
                pass
            print(f"Upload route {self.path}: forwarding failed ({type(error).__name__})", flush=True)
        finally:
            connection.close()


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", PORT), UploadHandler)
    server.daemon_threads = True
    print(f"BTIR emulator upload bridge listening on 127.0.0.1:{PORT}", flush=True)
    server.serve_forever()
