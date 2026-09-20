#!/usr/bin/env python3
"""Minimal webhook receiver: the automated process an alert triggers.

Alertmanager POSTs firing/resolved alerts here. Each one is logged to stdout
(so it also flows into Loki via Promtail) and appended to /data/alerts.log,
so the alert -> automated-action chain is verifiable after the fact.

Deliberately stdlib-only: no dependencies to install, nothing to keep patched.
"""
import datetime
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG_PATH = "/data/alerts.log"
PORT = int(os.environ.get("PORT", "5001"))


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            payload = json.loads(raw or b"{}")
        except json.JSONDecodeError:
            payload = {"raw": raw.decode("utf-8", "replace")}

        lines = []
        for a in payload.get("alerts") or [payload]:
            labels = a.get("labels", {})
            annotations = a.get("annotations", {})
            lines.append(json.dumps({
                "ts": now(),
                "event": "alert_received",
                "status": a.get("status", payload.get("status", "unknown")),
                "alertname": labels.get("alertname", "unknown"),
                "severity": labels.get("severity", "unknown"),
                "container": labels.get("name", labels.get("instance", "-")),
                "summary": annotations.get("summary", ""),
                "runbook": annotations.get("runbook", ""),
                # This is where a real integration would page someone, open a
                # ticket, restart the workload, or scale it out.
                "action_taken": "recorded to /data/alerts.log",
            }))

        for line in lines:
            print(line, flush=True)

        try:
            os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
            with open(LOG_PATH, "a", encoding="utf-8") as fh:
                fh.write("\n".join(lines) + "\n")
        except OSError as exc:
            print(json.dumps({"ts": now(), "event": "write_failed", "error": str(exc)}), flush=True)

        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'{"ok":true}')

    def do_GET(self):
        """GET /alerts returns what has been received (handy for proof capture)."""
        if self.path.startswith("/alerts"):
            try:
                with open(LOG_PATH, encoding="utf-8") as fh:
                    body = fh.read().encode()
            except OSError:
                body = b""
        else:
            body = b'{"ok":true,"hint":"POST /alert, GET /alerts"}'
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass  # suppress default access logging; we emit structured lines instead


if __name__ == "__main__":
    print(json.dumps({"ts": now(), "event": "listening", "port": PORT}), flush=True)
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
