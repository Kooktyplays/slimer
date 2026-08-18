#!/usr/bin/env python3
"""Static dev server for the site, with caching turned off.

Python's stock http.server honours If-Modified-Since, which means an edited CSS
or JS file keeps serving from the browser cache and you spend your time
debugging a stale page. This sends no-store on everything instead.

    python3 site/tools/serve.py [port]
"""

import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

SITE = Path(__file__).resolve().parent.parent


class NoCacheHandler(SimpleHTTPRequestHandler):
    # The Godot export needs these two served correctly to boot at all.
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".webp": "image/webp",
        ".js": "text/javascript",
    }

    def end_headers(self):
        self.send_header("Cache-Control", "no-store, must-revalidate")
        super().end_headers()

    def send_header(self, keyword, value):
        # Drop the validators that let the browser serve a stale copy.
        if keyword.lower() in ("last-modified", "etag"):
            return
        super().send_header(keyword, value)

    def log_message(self, fmt, *args):
        # Quiet unless something actually went wrong.
        if args and str(args[1]).startswith(("4", "5")):
            super().log_message(fmt, *args)


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8181
    handler = partial(NoCacheHandler, directory=str(SITE))
    server = ThreadingHTTPServer(("127.0.0.1", port), handler)
    print(f"serving {SITE} at http://localhost:{port} (no cache)")
    server.serve_forever()


if __name__ == "__main__":
    main()
