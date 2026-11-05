import SwiftUI

/// The home tabs, covered as a whole by pages in the outer navigation stack.
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
        AppNavigation { HomeTabs() }
            .overlay { ToastHost() }
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

}

/// The home page owns both bars and their controls. TabView does not forward
/// its children's navigation items to an enclosing NavigationStack.
private struct HomeTabs: View {
    @Environment(AppGraph.self) private var graph
    @State private var searching = false
    @State private var noticeKind: NoticeKind = .comments
    @State private var width: CGFloat = 0

    var body: some View {
        let unread = graph.unread.state.any
        return TabView(selection: graph.router.selection) {
            Tab("首页", systemImage: "house", value: AppTab.home) {
                TabRoot(tab: .home) { TimelinePage() }
            }
            Tab("搜索", systemImage: "magnifyingglass", value: AppTab.search) {
                TabRoot(tab: .search) { SearchPage(searching: $searching) }
            }
            if graph.session.state.uid != nil {
                Tab("通知", systemImage: "bell", value: AppTab.notifications) {
                    TabRoot(tab: .notifications) { NotificationsPage(kind: $noticeKind) }
                }
                .badge(unread ? Text(verbatim: "") : nil)
            }
            Tab("设置", systemImage: "gearshape", value: AppTab.settings) {
                TabRoot(tab: .settings) { SettingsPage() }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { homeToolbar }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
    }

    private var title: String {
        switch graph.router.tab {
        case .home: ""
        case .search: "搜索"
        case .notifications: "通知"
        case .settings: "设置"
        }
    }

    @ToolbarContentBuilder private var homeToolbar: some ToolbarContent {
        if graph.router.tab == .home { TimelineToolbar() }
        if graph.router.tab == .search, graph.session.account != nil {
            ToolbarItem(placement: .primaryAction) {
                Button(searching ? "取消搜索" : "搜索微博", systemImage: searching ? "xmark" : "magnifyingglass") {
                    searching.toggle()
                }
                .labelStyle(.iconOnly)
            }
        }
        if graph.router.tab == .notifications, graph.session.account != nil {
            ToolbarItem(placement: .principal) {
                NotificationKindBar(kind: $noticeKind).frame(width: min(max(width - 32, 0), 400))
            }
            .sharedBackgroundVisibility(.hidden)
        }
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

/// Pushes every secondary page over the entire home, including its tab bar.
/// The system owns both the push transition and interactive back navigation.
struct AppNavigation<Root: View>: View {
    @ViewBuilder let root: () -> Root
    @Environment(AppGraph.self) private var graph

    var body: some View {
        NavigationStack(path: graph.router.path(graph.router.tab)) {
            root()
                .navigationDestination(for: Route.self) { route in
                    RouteView(route: route)
                        .environment(
                            \.isCurrentNavigationPage, graph.router.paths[graph.router.tab]?.last == route
                        )
                }
        }
    }
}

/// Only the selected home tab may react to scrolling while home is visible.
private struct TabRoot<Root: View>: View {
    let tab: AppTab
    @ViewBuilder let root: () -> Root
    @Environment(AppGraph.self) private var graph

    var body: some View {
        root().environment(
            \.isCurrentNavigationPage, graph.router.tab == tab && graph.router.paths[tab, default: []].isEmpty
        )
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
            if let context = graph.forAccount(key) {
                AnyView(RouteView(route: route).environment(context))
            } else {
                AnyView(AccountsPage())
            }
        case .status(let id, let initial): StatusDetailPage(id: id, initial: initial)
        case .comments(let thread): CommentRepliesPage(thread: thread)
        case .profile(let uid, let initial): ProfilePage(uid: uid, initial: initial)
        case .profileByName(let name): ProfilePage(screenName: name)
        case .searchResults(let query): SearchResultsPage(query: query)
        case .web(let url):
            if let owner = graph.router.accountKey {
                AccountWebPage(owner: owner, url: url)
            } else {
                InAppBrowser(url: url)
            }
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
