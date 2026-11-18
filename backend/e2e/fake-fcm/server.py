"""Recording stand-in for Google OAuth and the FCM v1 API (E2E only).

The API's real FirebaseSender talks to this server in the local E2E stack:
  POST /token                               -> fake OAuth access token
  POST /v1/projects/<project>/messages:send -> message is recorded
The E2E suite inspects and resets the recording through:
  GET    /messages
  DELETE /messages
Nothing here is reachable outside the compose network and the loopback port.
"""

import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

_lock = threading.Lock()
_messages = []


class Handler(BaseHTTPRequestHandler):
    def _reply(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length) if length else b""

    def do_POST(self):
        raw = self._body()
        if self.path == "/token":
            self._reply(200, {"access_token": "e2e-fake-access-token", "token_type": "Bearer", "expires_in": 3600})
            return
        if self.path.startswith("/v1/projects/") and self.path.endswith("/messages:send"):
            if self.headers.get("Authorization") != "Bearer e2e-fake-access-token":
                self._reply(401, {"error": "missing fake OAuth token"})
                return
            try:
                message = json.loads(raw or b"{}").get("message", {})
            except ValueError:
                self._reply(400, {"error": "invalid JSON"})
                return
            with _lock:
                _messages.append(message)
                name = "projects/e2e/messages/%d" % len(_messages)
            self._reply(200, {"name": name})
            return
        self._reply(404, {"error": "not found"})

    def do_GET(self):
        if self.path == "/messages":
            with _lock:
                self._reply(200, {"messages": list(_messages)})
            return
        if self.path == "/health":
            self._reply(200, {"status": "ok"})
            return
        self._reply(404, {"error": "not found"})

    def do_DELETE(self):
        if self.path == "/messages":
            with _lock:
                _messages.clear()
            self._reply(200, {"status": "cleared"})
            return
        self._reply(404, {"error": "not found"})

    def log_message(self, fmt, *args):
        print("fake-fcm: " + (fmt % args), flush=True)


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8090), Handler).serve_forever()
