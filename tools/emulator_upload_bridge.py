#!/usr/bin/env python3
"""Stream HarmonyOS emulator uploads through the host's TLS stack.

The emulator reaches host loopback at 10.0.2.2. The service binds only to
127.0.0.1 and keeps at most four 1 MiB chunks in memory per upload. Case data
is forwarded to the configured server and is never written to disk.
"""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import http.client
import json
from queue import Empty, Full, Queue
import re
import secrets
from threading import Event, Lock, Thread
import time


HOST = "btir-online.ai-premol.cn"
PORT = 18766
MAX_BODY = 512 * 1024 * 1024
MAX_CHUNK = 1024 * 1024
UPLOAD_PATHS = frozenset(("/tasks/3d", "/tasks/3d/archive"))
SESSIONS = {}
SESSIONS_LOCK = Lock()


def validate_upload_info(fields, files):
    if not isinstance(fields, dict) or len(fields) > 16:
        raise ValueError("Invalid form fields")
    for name, value in fields.items():
        if not isinstance(name, str) or not re.fullmatch(r"[a-z][a-z0-9_]{0,63}", name):
            raise ValueError("Invalid form field name")
        if not isinstance(value, str) or len(value.encode("utf-8")) > 2048:
            raise ValueError("Invalid form field value")
    if not isinstance(files, list) or not 1 <= len(files) <= 5:
        raise ValueError("Invalid file metadata")
    for item in files:
        if not isinstance(item, dict):
            raise ValueError("Invalid file metadata")
        name, filename, content_type, size = (item.get(key) for key in ("fieldName", "fileName", "contentType", "size"))
        if not isinstance(name, str) or not re.fullmatch(r"[a-z][a-z0-9_]{0,63}", name):
            raise ValueError("Invalid file field name")
        if not isinstance(filename, str) or len(filename.encode("utf-8")) > 255:
            raise ValueError("Invalid file name")
        if not isinstance(content_type, str) or not re.fullmatch(r"[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+", content_type):
            raise ValueError("Invalid file content type")
        if type(size) is not int or size < 0 or size > MAX_BODY:
            raise ValueError("Invalid file size")


def multipart_parts(fields: dict, files: list):
    boundary = ("BTIR" + secrets.token_hex(16)).encode("ascii")
    prefix = b"".join(
        b"--" + boundary + b"\r\n"
        + b'Content-Disposition: form-data; name="' + name.encode("ascii") + b'"\r\n\r\n'
        + value.encode("utf-8") + b"\r\n"
        for name, value in fields.items()
    )
    headers = []
    for item in files:
        filename = re.sub(r"[^A-Za-z0-9._-]", "_", item["fileName"].replace("\\", "/").split("/")[-1])
        headers.append(
            b"--" + boundary + b"\r\n"
            + b'Content-Disposition: form-data; name="' + item["fieldName"].encode("ascii")
            + b'"; filename="' + filename.encode("ascii") + b'"\r\n'
            + b"Content-Type: " + item["contentType"].encode("ascii") + b"\r\n\r\n"
        )
    closing = b"--" + boundary + b"--\r\n"
    length = len(prefix) + len(closing) + sum(len(header) + item["size"] + 2 for header, item in zip(headers, files))
    return boundary, prefix, headers, closing, length


class UploadSession:
    def __init__(self, path, authorization, fields, files):
        self.path = path
        self.authorization = authorization
        self.files = files
        self.boundary, self.prefix, self.headers, self.closing, self.length = multipart_parts(fields, files)
        if self.length > MAX_BODY:
            raise ValueError("Upload exceeds the server limit")
        self.queue = Queue(maxsize=4)
        self.lock = Lock()
        self.done = Event()
        self.cancelled = Event()
        self.received = [0] * len(files)
        self.next_index = next((i for i, item in enumerate(files) if item["size"]), len(files))
        self.result = None
        self.started = time.monotonic()

    def run(self):
        connection = http.client.HTTPSConnection(HOST, timeout=600)
        try:
            connection.putrequest("POST", self.path)
            connection.putheader("Content-Type", f"multipart/form-data; boundary={self.boundary.decode('ascii')}")
            connection.putheader("Content-Length", str(self.length))
            if self.authorization:
                connection.putheader("Authorization", self.authorization)
            connection.endheaders()
            connection.send(self.prefix)
            for index, (item, header) in enumerate(zip(self.files, self.headers)):
                connection.send(header)
                remaining = item["size"]
                while remaining:
                    try:
                        chunk_index, chunk = self.queue.get(timeout=120)
                    except Empty as error:
                        raise TimeoutError("Upload chunks stopped arriving") from error
                    if self.cancelled.is_set() or chunk_index != index or not chunk or len(chunk) > remaining:
                        raise ValueError("Invalid upload chunk sequence")
                    connection.send(chunk)
                    remaining -= len(chunk)
                connection.send(b"\r\n")
            connection.send(self.closing)
            response = connection.getresponse()
            self.result = (response.status, response.read(), response.getheader("Content-Type", "application/json"))
            print(f"Upload route {self.path}: {self.length} bytes, HTTP {response.status}", flush=True)
        except Exception as error:
            self.result = (502, json.dumps({"detail": f"Upload bridge failed: {type(error).__name__}"}).encode(), "application/json")
            print(f"Upload route {self.path}: forwarding failed ({type(error).__name__})", flush=True)
        finally:
            connection.close()
            self.done.set()


class UploadHandler(BaseHTTPRequestHandler):
    def log_message(self, format_string, *args):
        # Never log file names, bearer tokens, request bodies, or responses.
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
        if self.path == "/healthz":
            self.reply(200, b'{"service":"btir-emulator-upload-bridge"}')
        else:
            self.reply(404, b"{}")

    def do_POST(self):
        if self.path == "/stream/start":
            self.start_stream()
            return
        match = re.fullmatch(r"/stream/(chunk|finish|abort)/([0-9a-f]{32})(?:/([0-4]))?", self.path)
        if match:
            action, session_id, index_text = match.groups()
            with SESSIONS_LOCK:
                session = SESSIONS.get(session_id)
            if session is None:
                self.reply(404, b'{"detail":"Upload session not found"}')
            elif action == "chunk" and index_text is not None:
                self.stream_chunk(session, int(index_text))
            elif action == "finish" and index_text is None:
                self.finish_stream(session_id, session)
            elif action == "abort" and index_text is None:
                session.cancelled.set()
                try:
                    session.queue.put_nowait((None, None))
                except Full:
                    pass
                with SESSIONS_LOCK:
                    SESSIONS.pop(session_id, None)
                self.reply(204, b"")
            else:
                self.reply(404, b"{}")
        elif self.path in UPLOAD_PATHS:
            self.reply(426, b'{"detail":"Please install the latest BTIR app for emulator uploads"}')
        else:
            self.reply(404, b"{}")

    def start_stream(self):
        if self.headers.get("Transfer-Encoding"):
            self.reply(400, b'{"detail":"Transfer-Encoding is not supported"}')
            return
        try:
            length = int(self.headers["Content-Length"])
            if not 0 < length <= 16384:
                raise ValueError("Invalid session metadata length")
            request = json.loads(self.rfile.read(length))
            if not isinstance(request, dict) or request.get("path") not in UPLOAD_PATHS:
                raise ValueError("Invalid upload path")
            fields, files = request.get("fields", {}), request.get("files")
            validate_upload_info(fields, files)
            session = UploadSession(request["path"], self.headers.get("Authorization"), fields, files)
        except (KeyError, TypeError, ValueError):
            self.reply(400, b'{"detail":"Invalid upload session metadata"}')
            return
        with SESSIONS_LOCK:
            for key, existing in list(SESSIONS.items()):
                if existing.done.is_set() and time.monotonic() - existing.started > 600:
                    SESSIONS.pop(key, None)
            if len(SESSIONS) >= 2:
                self.reply(429, b'{"detail":"Too many upload sessions"}')
                return
            session_id = secrets.token_hex(16)
            SESSIONS[session_id] = session
        Thread(target=session.run, daemon=True).start()
        self.reply(201, json.dumps({"sessionId": session_id}).encode())

    def stream_chunk(self, session: UploadSession, index: int):
        if self.headers.get("Transfer-Encoding"):
            self.reply(400, b'{"detail":"Transfer-Encoding is not supported"}')
            return
        try:
            length = int(self.headers["Content-Length"])
        except (KeyError, TypeError, ValueError):
            self.reply(411, b'{"detail":"Content-Length is required"}')
            return
        if not 0 < length <= MAX_CHUNK:
            self.reply(413, b'{"detail":"Invalid upload chunk length"}')
            return
        data = self.rfile.read(length)
        if len(data) != length:
            self.reply(400, b'{"detail":"Incomplete upload chunk"}')
            return
        with session.lock:
            if session.done.is_set() or session.cancelled.is_set():
                self.reply(409, b'{"detail":"Upload session is closed"}')
                return
            if index != session.next_index or length > session.files[index]["size"] - session.received[index]:
                self.reply(400, b'{"detail":"Unexpected upload chunk"}')
                return
            while True:
                try:
                    session.queue.put((index, data), timeout=1)
                    break
                except Full:
                    if session.done.is_set():
                        self.reply(502, b'{"detail":"Upload forwarding stopped"}')
                        return
            session.received[index] += length
            if session.received[index] == session.files[index]["size"]:
                session.next_index = next(
                    (i for i in range(index + 1, len(session.files)) if session.files[i]["size"]),
                    len(session.files),
                )
        self.reply(204, b"")

    def finish_stream(self, session_id: str, session: UploadSession):
        with session.lock:
            complete = all(count == item["size"] for count, item in zip(session.received, session.files))
        if not complete:
            self.reply(400, b'{"detail":"Upload session is incomplete"}')
            return
        if not session.done.wait(timeout=610):
            session.cancelled.set()
            result = (504, b'{"detail":"Upload forwarding timed out"}', "application/json")
        else:
            result = session.result
        with SESSIONS_LOCK:
            SESSIONS.pop(session_id, None)
        self.reply(*result)


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", PORT), UploadHandler)
    server.daemon_threads = True
    print(f"BTIR emulator upload bridge listening on 127.0.0.1:{PORT}", flush=True)
    server.serve_forever()
