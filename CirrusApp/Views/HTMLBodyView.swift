import SwiftUI
import WebKit

/// Renders message HTML in a WKWebView with JavaScript off and remote content blocked by content rule lists.
/// Remote images load only when `allowRemoteImages` is set; stylesheets, fonts, media and scripts never load from the network.
struct HTMLBodyView: UIViewRepresentable {
    let html: String
    let allowRemoteImages: Bool
    @Binding var height: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.backgroundColor = .clear
        web.navigationDelegate = context.coordinator
        context.coordinator.observe(web)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.height = $height
        context.coordinator.load(html: html, allowImages: allowRemoteImages, dark: colorScheme == .dark, in: web)
    }

    // MARK: Content rules

    @MainActor enum Rules {
        private static var cache: [String: WKContentRuleList] = [:]

        /// Always on: no remote stylesheets, fonts, media, scripts, fetches or pings.
        private static let base = """
        [{"trigger":{"url-filter":"^(https?|ftp|wss?)://","resource-type":["style-sheet","font","media","script","raw","ping","popup","svg-document"]},"action":{"type":"block"}}]
        """
        /// Off once the reader taps "Load images".
        private static let images = """
        [{"trigger":{"url-filter":"^(https?|ftp)://","resource-type":["image"]},"action":{"type":"block"}}]
        """

        static func lists(allowImages: Bool) async -> [WKContentRuleList] {
            var out: [WKContentRuleList] = []
            for (id, json) in [("cirrus.base", base)] + (allowImages ? [] : [("cirrus.images", images)]) {
                if let hit = cache[id] { out.append(hit); continue }
                if let list = try? await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: id, encodedContentRuleList: json) {
                    cache[id] = list
                    out.append(list)
                }
            }
            return out
        }
    }

    // MARK: Document

    /// Wraps the message in a page with a strict CSP and fit-to-width rules.
    static func document(_ html: String, allowImages: Bool, dark: Bool) -> String {
        let img = allowImages ? "img-src https: http: data:" : "img-src data:"
        // Messages that bring their own colours are shown on white so dark mode does not make them unreadable.
        let hasOwnColors = html.range(of: #"(?i)(bgcolor|background|color\s*[:=])"#, options: .regularExpression) != nil
        let paper = dark && hasOwnColors
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; \(img)">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: \(paper ? "light" : "light dark"); }
        html, body { margin: 0; padding: 0; }
        body { font: -apple-system-body; overflow-wrap: anywhere; \(paper ? "background:#fff;color:#111;padding:8px;border-radius:8px;" : "") }
        img { max-width: 100% !important; height: auto !important; }
        table { max-width: 100% !important; }
        pre { white-space: pre-wrap; }
        a { color: -apple-system-blue; }
        </style></head><body>\(html)</body></html>
        """
    }

    // MARK: Coordinator

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        var height: Binding<CGFloat>
        private var lastKey: String?
        private var loadTask: Task<Void, Never>?
        private var observation: NSKeyValueObservation?

        init(height: Binding<CGFloat>) { self.height = height }

        func observe(_ web: WKWebView) {
            observation = web.scrollView.observe(\.contentSize, options: [.new]) { [weak self] scroll, _ in
                // KVO for a UIKit view is delivered on the main thread.
                let h = MainActor.assumeIsolated { scroll.contentSize.height }
                Task { @MainActor in
                    guard let self, h > 1, abs(self.height.wrappedValue - h) > 0.5 else { return }
                    self.height.wrappedValue = h
                }
            }
        }

        func load(html: String, allowImages: Bool, dark: Bool, in web: WKWebView) {
            let key = "\(allowImages)|\(dark)|\(html.hashValue)"
            guard key != lastKey else { return }
            lastKey = key
            loadTask?.cancel()
            loadTask = Task { [weak web] in
                let lists = await Rules.lists(allowImages: allowImages)
                guard !Task.isCancelled, let web else { return }
                let controller = web.configuration.userContentController
                controller.removeAllContentRuleLists()
                lists.forEach(controller.add)
                web.loadHTMLString(HTMLBodyView.document(html, allowImages: allowImages, dark: dark), baseURL: nil)
            }
        }

        // Links open in Safari; the message itself is the only thing that ever loads in the web view.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url, ["http", "https", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") {
                    await UIApplication.shared.open(url)
                }
                return .cancel
            }
            let isInitial = navigationAction.targetFrame?.isMainFrame == true && navigationAction.request.url?.scheme == "about"
            return isInitial ? .allow : .cancel
        }
    }
}
