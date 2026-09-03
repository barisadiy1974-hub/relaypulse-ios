import SwiftUI
import WebKit

/// Basit tam ekran WKWebView — Anyone dashboard / blog için.
struct WebPage: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.load(URLRequest(url: url))
        context.coordinator.web = web
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebPage
        weak var web: WKWebView?
        init(_ p: WebPage) { parent = p }
        func webView(_ w: WKWebView, didStartProvisionalNavigation n: WKNavigation!) {
            DispatchQueue.main.async { self.parent.isLoading = true }
        }
        func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }
        func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }
    }
}

/// Bir web sayfasını yükleyen, yükleme çubuğu + yeniden yükle olan sarmalayıcı.
struct WebDashboardView: View {
    let title: String
    let url: URL
    @State private var isLoading = true
    @State private var reloadToken = UUID()

    var body: some View {
        WebPage(url: url, isLoading: $isLoading)
            .id(reloadToken)
            .overlay(alignment: .top) {
                if isLoading {
                    ProgressView().progressViewStyle(.linear)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { reloadToken = UUID() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
    }
}
