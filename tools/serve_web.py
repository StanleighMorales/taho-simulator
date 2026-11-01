#!/usr/bin/env python3
"""Serve the exported web build for local testing.

A Godot web build cannot be opened over file:// — the browser blocks the wasm
and pck fetches. Run this instead:

    python tools/serve_web.py

Pass --isolated if you ever switch the export to thread support
(variant/thread_support=true); that build needs cross-origin isolation, and
this flag reproduces locally the COOP/COEP headers your host would have to set.
Without threads you do not need it, which is the whole reason the project can
deploy to GitHub Pages.
"""

import argparse
import functools
import http.server
import mimetypes
import pathlib
import socketserver

# Python's mimetypes DB does not reliably know these, and a wrong type on the
# wasm breaks WebAssembly.instantiateStreaming in Chrome.
mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("application/javascript", ".js")
mimetypes.add_type("application/octet-stream", ".pck")


class Handler(http.server.SimpleHTTPRequestHandler):
    isolated = False

    def end_headers(self):
        # Always fresh: stale wasm/pck after a re-export is a confusing bug.
        self.send_header("Cache-Control", "no-store")
        if self.isolated:
            self.send_header("Cross-Origin-Opener-Policy", "same-origin")
            self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()

    def log_message(self, fmt, *args):
        print("  %s" % (fmt % args))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8060)
    parser.add_argument("--dir", default="build/web")
    parser.add_argument("--isolated", action="store_true",
                        help="send COOP/COEP headers (only needed for thread-enabled builds)")
    args = parser.parse_args()

    root = pathlib.Path(args.dir).resolve()
    if not (root / "index.html").exists():
        print("No build found at %s" % root)
        print("Export first, then run this again.")
        return 1

    Handler.isolated = args.isolated
    handler = functools.partial(Handler, directory=str(root))

    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", args.port), handler) as httpd:
        print("Serving %s" % root)
        print("Open http://127.0.0.1:%d/  (cross-origin isolation: %s)"
              % (args.port, "on" if args.isolated else "off"))
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nStopped.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
