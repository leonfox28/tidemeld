import SwiftUI
import WebKit

/// Weibo's own sign-in page; after signing in it returns to weibo.com.
let loginURL = URL(
    string: "https://passport.weibo.com/sso/signin?entry=miniblog&source=miniblog&url=https%3A%2F%2Fweibo.com%2F")!

/// Hosts Weibo's official login page in a web view. The password is typed into
/// Weibo's page and never passes through maxbo.
///
/// After every main-frame load the web view's cookies are checked against the
/// API, wherever the page landed: passport sets the weibo.com cookies before
/// its cross-domain hop through login.sina.com.cn, and that hop can fail (HTTP
/// 403 inside a web view) without affecting the weibo.com session.
///
/// Closes once signed in, saying so.
struct LoginPage: View {
    @Environment(AppGraph.self) private var graph
    @Environment(\.dismiss) private var dismiss
    @State private var page = WebPage(navigationDecider: WebOnlyNavigation())
    @State private var verifying = false
    /// A SUB the API identified as a visitor's; not checked again until the
    /// web view has another.
    @State private var visitorSub: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("下方是微博官方登录页面。maxbo 不会接触你的密码，登录状态只保存在本机。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppTheme.elevated)
                if page.isLoading {
                    ProgressView(value: page.estimatedProgress).progressViewStyle(.linear)
                }
                WebView(page)
                    .overlay {
                        if verifying {
                            ProgressView()
                                .controlSize(.large)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(.black.opacity(0.26))
                        }
                    }
            }
            .navigationTitle("登录微博")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("刷新", systemImage: "arrow.clockwise") { page.reload() }
                }
            }
        }
        .onAppear {
            guard page.url == nil else { return }
            page.customUserAgent = browserUserAgent
            page.load(loginURL)
        }
        .onChange(of: page.isLoading) { _, loading in
            if !loading { check() }
        }
    }

    /// Checks the web view's cookies after each page, and signs in with them
    /// once they're a user's.
    private func check() {
        guard !verifying else { return }
        Task {
            let cookies = await graph.webCookies.readWeiboCookies()
            let sub = cookies[WeiboCookieJar.web]?["SUB"]
            devLog(
                "login check: weibo.com=\(cookies[WeiboCookieJar.web]?.keys.sorted() ?? []) "
                    + "weibo.cn=\(cookies[WeiboCookieJar.mobile]?.keys.sorted() ?? [])")
            guard let sub, sub != visitorSub, !verifying else { return }
            verifying = true
            defer { verifying = false }
            do {
                try await graph.session.completeLogin(cookies)
                dismiss()
                graph.toasts.show("登录成功")
            } catch WeiboError.sessionExpired {
                // Visitor cookies only: the user hasn't signed in yet.
                devLog("login check: not signed in yet")
                visitorSub = sub
            } catch {
                graph.toasts.show(loadErrorMessage(error))
            }
        }
    }
}

/// Shown in place of content that needs a signed-in user.
struct LoginPrompt: View {
    let expired: Bool
    @Environment(AppGraph.self) private var graph

    var body: some View {
        ContentUnavailableView {
            Label(expired ? "登录已过期，请重新登录" : "登录后即可浏览关注的人的微博", systemImage: "lock")
        } description: {
            Text("登录在微博官方页面中完成，maxbo 不会接触你的密码，登录状态只保存在本机。")
        } actions: {
            Button("登录微博") { graph.router.showingLogin = true }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
    }
}
