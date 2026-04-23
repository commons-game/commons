#!/usr/bin/env python3
"""Serve the Godot web export (nothreads build — plain HTTP, no cert needed).

Usage:
    python3 web/serve.py [port]   (default port: 8060)
"""

import http.server
import sys
import os

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8060


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        # COOP/COEP still good practice even on nothreads builds
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, fmt, *args):
        pass  # suppress per-request noise


os.chdir(os.path.dirname(os.path.abspath(__file__)))
print(f"Commons → http://192.168.8.189:{PORT}/")
http.server.HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
