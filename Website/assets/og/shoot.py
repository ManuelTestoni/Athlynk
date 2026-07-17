#!/usr/bin/env python3
"""Rebuild assets/og-cover.png from assets/og/og-cover.html.

The share image is the first thing anyone sees of Athlynk in WhatsApp,
LinkedIn or a Google result, so it is generated from a real page rather
than redrawn by hand — edit og-cover.html and re-run this.

    pip install playwright && playwright install chromium
    python3 assets/og/shoot.py
"""
import http.server
import functools
import pathlib
import socketserver
import threading

from playwright.sync_api import sync_playwright

ROOT = pathlib.Path(__file__).resolve().parents[2]   # Website/
OUT = ROOT / "assets" / "og-cover.png"
PORT = 8799


def main():
    handler = functools.partial(http.server.SimpleHTTPRequestHandler,
                                directory=str(ROOT))
    socketserver.TCPServer.allow_reuse_address = True
    srv = socketserver.TCPServer(("127.0.0.1", PORT), handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    try:
        with sync_playwright() as p:
            b = p.chromium.launch()
            pg = b.new_page(viewport={"width": 1200, "height": 630},
                            device_scale_factor=1)
            pg.goto(f"http://127.0.0.1:{PORT}/assets/og/og-cover.html",
                    wait_until="networkidle")
            pg.wait_for_timeout(600)          # let the webfonts settle
            pg.locator("#card").screenshot(path=str(OUT))
            b.close()
    finally:
        srv.shutdown()
    print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
