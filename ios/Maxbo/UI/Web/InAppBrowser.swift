import SwiftUI
import WebKit

/// A web page inside the app, for what maxbo has no page of its own for, such
/// as Weibo's own search results or its security checks.
///
/// It shares the web views' cookie store with the login page and sends the same
/// browser identity, so Weibo sees the signed-in user in the same browser.
/// Back, by button or swipe, steps back through the pages visited here before
/// leaving; once there are any, a close button leaves at once (as the Kotlin
/// page has them).
struct InAppBrowser: View {
    let url: URL
    /// Whether to offer the close button; not where the page is in a sheet
    /// with its own.
    var closable = true

    @Environment(AppGraph.self) private var graph
    @Environment(\.dismiss) private var dismiss
    @State private var page = WebPage(navigationDecider: WebOnlyNavigation())

    var body: some View {
        let previous = page.backForwardList.backList.last
        WebView(page)
            .webViewBackForwardNavigationGestures(.enabled)
            .tabBarHidesOnScroll(web: true)
            .overlay(alignment: .top) {
                if page.isLoading {
                    ProgressView(value: page.estimatedProgress).progressViewStyle(.linear)
                }
            }
            .navigationTitle(page.title)
            .navigationBarTitleDisplayMode(.inline)
            // In place of the system's, which would leave the page.
            .navigationBarBackButtonHidden(previous != nil)
            .toolbar {
                if let previous {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button("返回", systemImage: "chevron.backward") { _ = page.load(previous) }
                        if closable {
                            Button("关闭", systemImage: "xmark") { dismiss() }
                        }
                    }
                }
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
            InAppBrowser(url: request.url, closable: false)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) { dismiss() }
                    }
                }
        }
        .onDisappear { request.onClose?() }
    }
}
