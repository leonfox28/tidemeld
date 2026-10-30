import SwiftUI

/// The home tab: the signed-in user's timeline.
struct TimelinePage: View {
    @Environment(AppGraph.self) private var graph

    var body: some View {
        Group {
            switch graph.session.state {
            case .signedOut(let expired): LoginPrompt(expired: expired)
            case .signedIn(let account): Timeline(uid: account.uid)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
        .navigationTitle("首页")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            if graph.session.state.uid != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("发微博", systemImage: "square.and.pencil") { graph.router.showingCompose = true }
                }
            }
        }
    }
}

private struct Timeline: View {
    let uid: String
    @Environment(AppGraph.self) private var graph
    @State private var atTop = true
    @State private var pull = PullToRefresh()

    var body: some View {
        let timeline = graph.timeline
        ScrollViewReader { proxy in
            List {
                switch timeline.state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 160).plainRow()
                case .failed(let error):
                    ErrorRetry(error: error) { timeline.reload() }.padding(.top, 80).plainRow()
                case .ready(let state):
                    if state.items.isEmpty {
                        Text("还没有微博，下拉刷新试试")
                            .foregroundStyle(AppTheme.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 160)
                            .plainRow()
                    } else {
                        ForEach(state.items) { status in
                            StatusCard(status: status, actions: graph.statusActions)
                                .feedWidth()
                                .statusRow()
                        }
                        LoadMoreFooter(list: state) { Task { await timeline.loadMore() } }.plainRow()
                    }
                }
            }
            .listStyle(.plain)
            .appListStyle()
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
        graph.unread.requestCheck(minInterval: unreadRecheckInterval)
        do {
            try await graph.timeline.refresh()
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

    /// A home timeline's width: wider than a reading column, so a wide card can
    /// put its media beside its text.
    func feedWidth() -> some View { readingWidth(1000) }
}
