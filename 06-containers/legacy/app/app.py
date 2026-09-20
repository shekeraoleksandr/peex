#!/usr/bin/env python3
"""PeEx demo containerized app (stdlib only).

Endpoints:
  /         -> HTML status page (content driven by configuration/env vars)
  /healthz  -> liveness probe used by the container HEALTHCHECK
  /metrics  -> Prometheus-format metrics (observability)

Configuration comes entirely from environment variables so it can be changed
without rebuilding the image (12-factor style):
  APP_MESSAGE, APP_ENV, APP_VERSION, APP_COLOR
"""
import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

START = time.time()
REQUESTS = 0

CFG = {
    "message": os.getenv("APP_MESSAGE", "Hello from PeEx"),
    "env": os.getenv("APP_ENV", "dev"),
    "version": os.getenv("APP_VERSION", "1.0.0"),
    "color": os.getenv("APP_COLOR", "#2563eb"),
}


def log(event, **kw):
    """Structured JSON log line to stdout (observability)."""
    rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "event": event}
    rec.update(kw)
    print(json.dumps(rec), flush=True)


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="text/plain; charset=utf-8"):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        global REQUESTS
        REQUESTS += 1
        if self.path == "/healthz":
            self._send(200, "ok\n")
            log("request", path=self.path, status=200)
            return
        if self.path == "/metrics":
            uptime = time.time() - START
            body = (
                "# HELP app_up 1 if the app is up\n# TYPE app_up gauge\napp_up 1\n"
                "# HELP app_requests_total Total HTTP requests\n"
                "# TYPE app_requests_total counter\n"
                f"app_requests_total {REQUESTS}\n"
                "# HELP app_uptime_seconds Uptime in seconds\n"
                "# TYPE app_uptime_seconds gauge\n"
                f"app_uptime_seconds {uptime:.0f}\n"
            )
            self._send(200, body)
            log("request", path=self.path, status=200)
            return
        html = (
            f"<!doctype html><html><head><meta charset='utf-8'>"
            f"<title>PeEx container</title></head>"
            f"<body style='font-family:sans-serif;max-width:40rem;margin:3rem auto'>"
            f"<h1 style='color:{CFG['color']}'>{CFG['message']}</h1>"
            f"<p>Environment: <b>{CFG['env']}</b></p>"
            f"<p>Version: <b>{CFG['version']}</b></p>"
            f"<p>Served by the PeEx containerized app.</p></body></html>"
        )
        self._send(200, html, "text/html; charset=utf-8")
        log("request", path=self.path, status=200)

    def log_message(self, *_):
        pass  # replaced by structured JSON logging above


if __name__ == "__main__":
    port = int(os.getenv("APP_PORT", "8080"))
    log("startup", port=port, config=CFG, python=sys.version.split()[0])
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
