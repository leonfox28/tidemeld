import SwiftUI

/// The tabs, each with its own stack of pages, and what goes over them.
struct RootView: View {
    @Environment(AppGraph.self) private var graph
    /// The device's text size, which the text size setting moves from.
    @Environment(\.dynamicTypeSize) private var systemTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var media
    /// Whether the app went to the background since it was last opened.
    @State private var away = false

    var body: some View {
        let settings = graph.settings.settings
        tabs
            .modifier(Presentations(media: media))
            .environment(graph.toasts)
            .environment(\.mediaNamespace, media)
            .tint(AppTheme.accent)
            .preferredColorScheme(settings.themeMode.colorScheme)
            .dynamicTypeSize(settings.textSize.applied(to: systemTypeSize))
            // Checks for unread notifications when the user signs in or opens
            // the app, and when they come back to it (at most once a minute),
            // never in between (PLAN §2).
            .task(id: graph.session.state.uid) {
                if graph.session.state.uid != nil { await graph.unread.check() }
            }
            #if DEBUG
            .task { DebugLaunch.apply(graph) }
            #endif
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background: away = true
                case .active:
                    if away { graph.unread.requestCheck(minInterval: unreadRecheckInterval) }
                    away = false
                default: break
                }
            }
    }

    private var tabs: some View {
        let unread = graph.unread.state.any
        return TabView(selection: graph.router.selection) {
            Tab("首页", systemImage: "house", value: AppTab.home) {
                TabStack(tab: .home) { TimelinePage() }
            }
            Tab("搜索", systemImage: "magnifyingglass", value: AppTab.search) {
                TabStack(tab: .search) { SearchPage() }
            }
            if graph.session.state.uid != nil {
                Tab("通知", systemImage: "bell", value: AppTab.notifications) {
                    TabStack(tab: .notifications) { NotificationsPage() }
                }
                .badge(unread ? Text(verbatim: "") : nil)
            }
            Tab("设置", systemImage: "gearshape", value: AppTab.settings) {
                TabStack(tab: .settings) { SettingsPage() }
            }
        }
        .overlay { ToastHost() }
    }
}

/// Sheets, covers and dialogs over the whole app, as the router asks for them.
private struct Presentations: ViewModifier {
    let media: Namespace.ID
    @Environment(AppGraph.self) private var graph

    func body(content: Content) -> some View {
        @Bindable var router = graph.router
        let context = router.presentationAccount.flatMap { graph.forAccount($0) } ?? graph
        content
            .sheet(isPresented: $router.showingLogin) { LoginFlowPage() }
            .sheet(isPresented: $router.showingCompose) { ComposePage().environment(context) }
            .sheet(item: $router.repost) { RepostSheet(request: $0).environment(context) }
            .sheet(item: $router.commentComposer) { CommentComposer(request: $0).environment(context) }
            .sheet(item: $router.web, onDismiss: {}) { WebSheet(request: $0).environment(context) }
            .fullScreenCover(item: $router.viewer) { request in
                ImageViewer(request: request).environment(context)
                    .modifier(ZoomTransition(sourceID: request.sourceID, namespace: media))
            }
            .fullScreenCover(item: $router.video) { VideoPlayerPage(request: $0).environment(context) }
            .confirmationDialog(
                "确定删除这条微博吗？", isPresented: deleting, titleVisibility: .visible,
                presenting: router.deletion
            ) { request in
                Button("删除", role: .destructive) { context.confirmDelete(request) }
            }
    }

    private var deleting: Binding<Bool> {
        Binding(get: { graph.router.deletion != nil }, set: { if !$0 { graph.router.deletion = nil } })
    }
}

/// A tab's stack of pages.
private struct TabStack<Root: View>: View {
    let tab: AppTab
    @ViewBuilder let root: () -> Root
    @Environment(AppGraph.self) private var graph

    var body: some View {
        NavigationStack(path: graph.router.path(tab)) {
            root()
                .environment(
                    \.isCurrentNavigationPage, graph.router.tab == tab && graph.router.paths[tab, default: []].isEmpty
                )
                .navigationDestination(for: Route.self) { route in
                    RouteView(route: route)
                        .environment(
                            \.isCurrentNavigationPage, graph.router.tab == tab && graph.router.paths[tab]?.last == route
                        )
                }
        }
    }
}

/// The page of [route].
struct RouteView: View {
    let route: Route
    @Environment(AppGraph.self) private var graph

    var body: some View {
        switch route {
        case .accounts: AccountsPage()
        case .account(let key, let route):
            if let context = graph.forAccount(key) { AnyView(RouteView(route: route).environment(context)) }
            else { AnyView(AccountsPage()) }
        case .status(let id, let initial): StatusDetailPage(id: id, initial: initial)
        case .comments(let thread): CommentRepliesPage(thread: thread)
        case .profile(let uid, let initial): ProfilePage(uid: uid, initial: initial)
        case .profileByName(let name): ProfilePage(screenName: name)
        case .searchResults(let query): SearchResultsPage(query: query)
        case .web(let url):
            if let owner = graph.router.accountKey { AccountWebPage(owner: owner, url: url) }
            else { InAppBrowser(url: url) }
        case .xStatus(let owner, let id, let initial): XDetailPage(owner: owner, id: id, initial: initial)
        case .accountWeb(let owner, let url): AccountWebPage(owner: owner, url: url)
        case .textSize: TextSizePage()
        case .about: AboutPage()
        case .privacy: PrivacyPage()
        case .licenses: LicensesPage()
        case .diagnostics: DiagnosticsPage()
        }
    }
}

/// Zooms a viewer out of the tile it was opened from, when there is one.
private struct ZoomTransition: ViewModifier {
    let sourceID: String?
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if let sourceID {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
    }
}
