import SwiftUI

/// The home tab: public posts for guests, the following feed after sign-in.
struct TimelinePage: View {
    @Environment(AppGraph.self) private var graph

    var body: some View {
        let uid = graph.session.state.uid
        Group {
            if graph.accounts.accounts.isEmpty && graph.settings.settings.feedSelection != .x { Timeline(uid: nil) }
            else { SocialTimeline() }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appBackground()
            .navigationTitle("")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Menu {
                        Picker("信息流", selection: Binding(get: { graph.settings.settings.feedSelection }, set: { choice in graph.settings.update { $0.feedSelection = choice } })) {
                            ForEach(FeedSelection.allCases) { Text($0.label).tag($0) }
                        }
                    } label: {
                        HStack(spacing: 4) { Text(graph.settings.settings.feedSelection.label).font(.headline); Image(systemName: "chevron.down").font(.caption) }
                    }
                    .accessibilityLabel("选择信息流")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("账号管理", systemImage: "person") { graph.router.push(.accounts) }
                        .labelStyle(.iconOnly)
                }
                if uid != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("发微博", systemImage: "square.and.pencil") { graph.router.showingCompose = true }
                    }
                }
            }
    }
}

private struct Timeline: View {
    let uid: String?
    @Environment(AppGraph.self) private var graph
    @State private var atTop = true
    @State private var pull = PullToRefresh()
    /// The page's width, which the timeline's column follows.
    @State private var width: CGFloat = 0

    var body: some View {
        let timeline = uid == nil ? graph.guestTimeline : graph.timeline
        ScrollViewReader { proxy in
            List {
                switch timeline.state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 160).plainRow()
                case .failed(let error):
                    ErrorRetry(error: error) { timeline.reload() }.padding(.top, 80).plainRow()
                case .ready(let state):
                    if state.items.isEmpty {
                        Text(uid == nil ? "暂时没有公开微博，下拉刷新试试" : "还没有微博，下拉刷新试试")
                            .foregroundStyle(AppTheme.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 160)
                            .plainRow()
                    } else {
                        ForEach(state.items) { status in
                            StatusCard(status: status, actions: uid == nil ? graph.guestStatusActions : graph.statusActions)
                                .feedWidth(in: width)
                                .statusRow()
                        }
                        if uid != nil {
                            LoadMoreFooter(list: state) { Task { await timeline.loadMore() } }.plainRow()
                        }
                    }
                    if uid == nil {
                        VStack(spacing: 10) {
                            Text("游客仅可浏览部分公开微博，登录后查看更多及参与互动。")
                                .font(.footnote).foregroundStyle(AppTheme.secondary)
                            Button("登录查看更多") { graph.router.showingLogin = true }
                        }
                        .frame(maxWidth: .infinity).padding(20).plainRow()
                    }
                }
            }
            .listStyle(.plain)
            .appListStyle()
            .loadsMoreAsScrolled()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .refreshable { await refresh() }
            .pullToRefresh(pull)
            .tabBarHidesOnScroll()
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y <= -geometry.contentInsets.top + 4
            } action: { _, top in
                atTop = top
            }
            // Tapping the open tab again: back to the top, or from there a
            // refresh, shown as on a pull.
            .onChange(of: graph.router.reselects[.home]) {
                if atTop {
                    if !pull.begin() { Task { await refresh() } }
                } else if let first = timeline.items.first {
                    withAnimation { proxy.scrollTo(first.id, anchor: .top) }
                }
            }
        }
        .task(id: uid) { timeline.start() }
    }

    private func refresh() async {
        // The user asked for what's new; that includes notifications.
        if uid != nil { graph.unread.requestCheck(minInterval: unreadRecheckInterval) }
        do {
            try await (uid == nil ? graph.guestTimeline : graph.timeline).refresh()
        } catch {
            graph.toasts.showError(error, router: graph.router)
        }
    }
}

extension View {
    /// A list row with nothing of a row's own: no insets, separator or fill.
    func plainRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    /// A status card as a list row, edge to edge, divided from the next.
    func statusRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(AppTheme.background)
            .listRowSeparatorTint(AppTheme.outline)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            // Nor from the top bar: a line over the first row would read as
            // the bar's edge, and a pull to refresh would bring it down with
            // the content, the spinner over it as if in the bar.
            .listSectionSeparator(.hidden, edges: .top)
    }

    /// A list section's header with no insets of its own: its content lines up
    /// with the rows under it.
    func listHeader() -> some View {
        listRowInsets(EdgeInsets())
    }

    /// At most a reading column wide, centred.
    func readingWidth(_ width: CGFloat = 640) -> some View {
        frame(maxWidth: width).frame(maxWidth: .infinity)
    }

    /// A home timeline's column in a page [width] wide: wider than a reading
    /// column once a card puts its media beside its text, else the reading
    /// column, as in the Kotlin app (`feedColumnWidth`).
    func feedWidth(in width: CGFloat) -> some View {
        readingWidth(width == 0 || width >= wideCardFrom ? 1000 : 640)
    }
}
