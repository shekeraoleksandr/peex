#!/usr/bin/env python3
"""Pre-configured demo app deployed by the pipeline (stdlib only).

Reads its configuration from a JSON file (APP_CONFIG env or default path) and
exposes /healthz, /version and / — so the deploy stage can be verified.
"""
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

CFG_PATH = os.getenv("APP_CONFIG", os.path.join(os.path.dirname(__file__), "..", "config", "app.config.json"))


def load_config():
    with open(CFG_PATH, encoding="utf-8") as fh:
        return json.load(fh)


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="text/plain; charset=utf-8"):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        cfg = load_config()
        if self.path == "/healthz":
            self._send(200, "ok\n")
        elif self.path == "/version":
            self._send(200, json.dumps({k: cfg[k] for k in ("name", "version", "environment")}),
                       "application/json")
        else:
            greeting = "Hello from PeEx CI/CD" if cfg.get("greeting_enabled") else "greeting disabled"
            self._send(200, f"{greeting} — v{cfg['version']} ({cfg['environment']})\n")

    def log_message(self, *_):
        pass


if __name__ == "__main__":
    port = int(os.getenv("APP_PORT", "8080"))
    print(f"serving on :{port} config={CFG_PATH}", flush=True)
    HTTPServer(("0.0.0.0", port), Handler).serve_forever()
