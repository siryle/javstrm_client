import SwiftUI
import WebKit
import JavStrmCore

struct WebDestination: Identifiable {
    let id = UUID()
    let title: String
    let path: String
    var query: [URLQueryItem] = []
}

struct WebPortalView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let destination: WebDestination
    @State private var webView: WKWebView?
    @State private var loading = true
    @State private var error: String?
    @State private var initialURL: URL?
    @State private var connectionID: UUID?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if loading { ProgressView().padding(10) }
                if let error {
                    ErrorPanel(message: error) { Task { await prepare() } }.padding()
                }
                if let webView, let initialURL {
                    PortalRepresentable(webView: webView, initialURL: initialURL, loading: $loading, error: $error)
                        .id(ObjectIdentifier(webView))
                }
            }
            .navigationTitle(destination.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { webView?.reload() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("刷新页面")
                }
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
            .task { await prepare() }
            .onDisappear {
                webView?.stopLoading()
                guard let webView, let connectionID else { return }
                Task {
                    let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                    let cookie = cookies.first { $0.name == "miyabi_token" && $0.domain == initialURL?.host }
                    let token = cookie.map { SessionToken(value: $0.value, expiresAt: $0.expiresDate) }
                    await session.adoptBrowserToken(token, connection: connectionID)
                }
            }
        }
    }

    private func prepare() async {
        guard let client = session.client else { return }
        loading = true
        error = nil
        do {
            let url = try client.address.endpoint(destination.path, query: destination.query)
            connectionID = session.connectionID
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            if let token = await client.currentToken(), token.isValid,
               let host = client.address.url.host {
                var properties: [HTTPCookiePropertyKey: Any] = [
                    .name: "miyabi_token", .value: token.value, .domain: host, .path: "/"
                ]
                if client.address.url.scheme == "https" { properties[.secure] = "TRUE" }
                if let expiration = token.expiresAt { properties[.expires] = expiration }
                properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
                if let cookie = HTTPCookie(properties: properties) {
                    await config.websiteDataStore.httpCookieStore.setCookie(cookie)
                }
            }
            guard !Task.isCancelled, connectionID == session.connectionID else { return }
            let view = WKWebView(frame: .zero, configuration: config)
            view.allowsBackForwardNavigationGestures = true
            view.isOpaque = false
            view.backgroundColor = .systemBackground
            initialURL = url
            webView = view
        } catch {
            self.error = session.describe(error)
            loading = false
        }
    }
}

private struct PortalRepresentable: UIViewRepresentable {
    let webView: WKWebView
    let initialURL: URL
    @Binding var loading: Bool
    @Binding var error: String?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.load(URLRequest(url: initialURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) { context.coordinator.parent = self }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: PortalRepresentable
        init(parent: PortalRepresentable) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.loading = true
            parent.error = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { parent.loading = false }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        private func fail(_ error: Error) {
            if (error as? URLError)?.code == .cancelled { return }
            parent.loading = false
            parent.error = error.localizedDescription
        }

        func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url,
                  ["http", "https", "about"].contains(url.scheme ?? "") else {
                decisionHandler(.cancel)
                return
            }
            let base = parent.initialURL
            let mainFrame = navigationAction.targetFrame?.isMainFrame != false
            let sameOrigin = url.scheme == base.scheme && url.host == base.host
                && (url.port ?? (url.scheme == "https" ? 443 : 80))
                == (base.port ?? (base.scheme == "https" ? 443 : 80))
            if mainFrame, url.scheme != "about", !sameOrigin {
                if navigationAction.navigationType == .linkActivated { UIApplication.shared.open(url) }
                decisionHandler(.cancel)
                return
            }
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
            } else { decisionHandler(.allow) }
        }

        func webView(
            _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void
        ) {
            present(webView, message: message, confirm: false) { _ in completionHandler() }
        }

        func webView(
            _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
        ) {
            present(webView, message: message, confirm: true, completion: completionHandler)
        }

        private func present(_ webView: WKWebView, message: String, confirm: Bool,
                             completion: @escaping @MainActor @Sendable (Bool) -> Void) {
            guard var controller = webView.window?.rootViewController else { completion(false); return }
            while let presented = controller.presentedViewController { controller = presented }
            let alert = UIAlertController(title: "JavStrm", message: message, preferredStyle: .alert)
            if confirm { alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completion(false) }) }
            alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completion(true) })
            controller.present(alert, animated: true)
        }
    }
}
