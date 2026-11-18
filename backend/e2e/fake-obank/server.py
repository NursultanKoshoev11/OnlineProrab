"""Recording stand-in for the O!Dengi JSON API (E2E only).

The API under test sends signed JSON requests to /api/json/json.php. This
server verifies the merchant request signature, implements only the two
commands used by the subscription checkout, and records every call.

Test controls:
  GET    /calls
  DELETE /calls
  PUT    /control/status   {"status":"approved"}
"""

import hashlib
import hmac
import itertools
import json
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


SID = os.environ.get("FAKE_OBANK_SID", "e2e-only-sid")
PASSWORD = os.environ.get("FAKE_OBANK_PASSWORD", "e2e-only-password")
PAYMENT_BASE = os.environ.get("FAKE_OBANK_PAYMENT_BASE", "http://fake-obank:8091")

_lock = threading.Lock()
_calls = []
_invoices = {}
_next_status = None
_invoice_numbers = itertools.count(1)


def json_bytes(payload):
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def request_signature(payload):
    unsigned = {
        "cmd": payload.get("cmd"),
        "version": payload.get("version"),
        "sid": payload.get("sid"),
        "mktime": payload.get("mktime"),
        "lang": payload.get("lang"),
        "data": payload.get("data"),
    }
    digest = hmac.new(PASSWORD.encode("utf-8"), json_bytes(unsigned), hashlib.md5)
    return digest.hexdigest()


class Handler(BaseHTTPRequestHandler):
    def _reply(self, status, payload):
        body = json_bytes(payload)
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length) if length else b""

    def _parse_json(self):
        try:
            return json.loads(self._body())
        except (TypeError, ValueError):
            self._reply(400, {"error": "invalid JSON"})
            return None

    def do_POST(self):
        if urlsplit(self.path).path != "/api/json/json.php":
            self._reply(404, {"error": "not found"})
            return

        payload = self._parse_json()
        if payload is None:
            return
        if payload.get("sid") != SID or payload.get("hash", "").lower() != request_signature(payload):
            self._reply(401, {"error": "invalid fake O!Bank request signature"})
            return
        if payload.get("version") != 1005 or payload.get("lang") != "ru":
            self._reply(400, {"error": "unexpected fake O!Bank request metadata"})
            return

        command = payload.get("cmd")
        data = payload.get("data") or {}
        with _lock:
            _calls.append({"command": command, "request": payload})

        if command == "createInvoice":
            self._create_invoice(data)
            return
        if command == "statusPayment":
            self._status_payment(data)
            return
        self._reply(400, {"error": "unsupported fake O!Bank command"})

    def _create_invoice(self, data):
        order_id = str(data.get("order_id") or "")
        amount = int(data.get("amount") or 0)
        currency = str(data.get("currency") or "")
        test = int(data.get("test") or 0)
        if not order_id or amount <= 0 or currency != "KGS":
            self._reply(400, {"error": "invalid createInvoice data"})
            return

        number = next(_invoice_numbers)
        invoice_id = "e2e-invoice-%d" % number
        with _lock:
            _invoices[invoice_id] = {
                "order_id": order_id,
                "amount": amount,
                "currency": currency,
                "test": test,
                "transaction_id": "e2e-transaction-%d" % number,
            }
        payment_url = "%s/pay/%s" % (PAYMENT_BASE.rstrip("/"), invoice_id)
        self._reply(
            200,
            {
                "data": {
                    "invoice_id": invoice_id,
                    "paylink_url": payment_url,
                    "site_pay": payment_url,
                    "link_app": "https://o.kg/l/a?t=wl_unpbill&id=%s" % invoice_id,
                }
            },
        )

    def _status_payment(self, data):
        global _next_status
        invoice_id = str(data.get("invoice_id") or "")
        order_id = str(data.get("order_id") or "")
        with _lock:
            invoice = _invoices.get(invoice_id)
            status = _next_status or "processing"
            if _next_status is not None:
                _next_status = None
        if invoice is None or invoice["order_id"] != order_id:
            self._reply(200, {"data": {"status": "canceled", "payments": []}})
            return

        payment_status = status
        payment = {
            "trans_id": invoice["transaction_id"],
            "amount": str(invoice["amount"]),
            "status": payment_status,
            "order_id": invoice["order_id"],
            "test": str(invoice["test"]),
        }
        self._reply(200, {"data": {"status": status, "payments": [payment]}})

    def do_GET(self):
        path = urlsplit(self.path).path
        if path == "/health":
            self._reply(200, {"status": "ok"})
            return
        if path == "/calls":
            with _lock:
                self._reply(200, {"calls": list(_calls)})
            return
        self._reply(404, {"error": "not found"})

    def do_DELETE(self):
        global _next_status
        if urlsplit(self.path).path != "/calls":
            self._reply(404, {"error": "not found"})
            return
        with _lock:
            _calls.clear()
            _next_status = None
        self._reply(200, {"status": "cleared"})

    def do_PUT(self):
        global _next_status
        if urlsplit(self.path).path != "/control/status":
            self._reply(404, {"error": "not found"})
            return
        payload = self._parse_json()
        if payload is None:
            return
        status = str(payload.get("status") or "").strip().lower()
        if status not in {"approved", "processing", "canceled", "cancelled"}:
            self._reply(400, {"error": "status must be approved, processing, or canceled"})
            return
        with _lock:
            _next_status = status
        self._reply(200, {"status": status})

    def log_message(self, fmt, *args):
        print("fake-obank: " + (fmt % args), flush=True)


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8091), Handler).serve_forever()
