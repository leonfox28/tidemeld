import SwiftUI
import WebKit

/// A web page inside the app, for what maxbo has no page of its own for, such
/// as Weibo's own search results or its security checks.
///
/// It shares the web views' cookie store with the login page and sends the same
/// browser identity, so Weibo sees the signed-in user in the same browser.
/// Swiping back steps back through the pages visited here.
struct InAppBrowser: View {
    let url: URL

    @Environment(AppGraph.self) private var graph
    @State private var page = WebPage(navigationDecider: WebOnlyNavigation())

    var body: some View {
        WebView(page)
            .webViewBackForwardNavigationGestures(.enabled)
            .overlay(alignment: .top) {
                if page.isLoading {
                    ProgressView(value: page.estimatedProgress).progressViewStyle(.linear)
                }
            }
            .navigationTitle(page.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu("更多", systemImage: "ellipsis") {
                        Button("刷新", systemImage: "arrow.clockwise") { page.reload() }
                        Button("在浏览器中打开", systemImage: "safari") { graph.openExternally(page.url ?? url) }
                    }
                }
            }
            .onAppear {
                guard page.url == nil else { return }
                page.customUserAgent = browserUserAgent
                page.load(url)
            }
    }
}

/// [InAppBrowser] over the app, as for a security check; going back from it
/// calls the request's `onClose`, e.g. to try a load again.
struct WebSheet: View {
    let request: WebRequest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            InAppBrowser(url: request.url)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) { dismiss() }
                    }
                }
        }
        .onDisappear { request.onClose?() }
    }
}
