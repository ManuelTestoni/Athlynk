//
//  AnimatedWebPView.swift
//  Renders an animated WebP — the exercises-dataset demo gif is stored as
//  animated WebP (converted server-side to save space), which SwiftUI's
//  AsyncImage/ImageIO can't decode frame-by-frame. WebKit does, natively, so
//  a tiny HTML wrapper sidesteps the need for a third-party decoder.
//

import SwiftUI
import WebKit

struct AnimatedWebPView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.isUserInteractionEnabled = false
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        let html = """
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html, body { margin: 0; padding: 0; background: transparent; height: 100%; }
          img { width: 100%; height: 100%; object-fit: cover; display: block; }
        </style></head>
        <body><img src="\(url.absoluteString)"></body></html>
        """
        web.loadHTMLString(html, baseURL: nil)
    }
}
