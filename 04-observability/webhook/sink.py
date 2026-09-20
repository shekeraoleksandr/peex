#!/usr/bin/env python3
"""Minimal webhook receiver: the 'automated process' an alert triggers.

Alertmanager POSTs firing/resolved alerts here; each is logged to stdout and
appended to /data/alerts.log so the trigger -> automated-action chain is
verifiable (docker compose logs webhook-sink, or read the file).
"""
import json
import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG_PATH = "/data/alerts.log"


class Handler(BaseHTTPRequestHandler):
    def _now(self):
        return datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            payload = json.loads(raw or b"{}")
        except json.JSONDecodeError:
            payload = {"raw": raw.decode("utf-8", "replace")}

        alerts = payload.get("alerts", [])
        for a in alerts or [payload]:
            name = a.get("labels", {}).get("alertname", "unknown")
            status = a.get("status", payload.get("status", "unknown"))
            summary = a.get("annotations", {}).get("summary", "")
            line = f"{self._now()} TRIGGERED action for alert={name} status={status} :: {summary}"
            print(line, flush=True)
            try:
                with open(LOG_PATH, "a", encoding="utf-8") as fh:
                    fh.write(line + "\n")
            except OSError as exc:
                print(f"{self._now()} WARN could not write {LOG_PATH}: {exc}", flush=True)

        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok\n")

    def do_GET(self):
        # simple health endpoint
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"webhook-sink ok\n")

    def log_message(self, *_):
        pass  # silence default access logging


if __name__ == "__main__":
    print("webhook-sink listening on :8080", flush=True)
    HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
