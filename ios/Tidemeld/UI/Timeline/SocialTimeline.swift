import SwiftUI

struct SocialTimeline: View {
    @Environment(AppGraph.self) private var graph
    @State private var width: CGFloat = 0
    @State private var atTop = true
    @State private var pull = PullToRefresh()
    var body: some View {
        let feed = graph.socialFeed
        let selection = graph.settings.settings.feedSelection
        let fingerprint =
            selection.rawValue
            + graph.accounts.accounts.map { "\($0.id):\($0.revision):\($0.expired)" }.joined(separator: ",")
        ScrollViewReader { proxy in
            List {
                if !feed.errors.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(feed.errors.keys.sorted(), id: \.self) { key in
                            Text(feed.errors[key] ?? "").font(.footnote).foregroundStyle(.red)
                        }
                        HStack {
                            Button("重试失败账号") { feed.retry() }
                            Button("账号管理") { graph.router.push(.accounts) }
                        }.buttonStyle(.borderless)
                    }.padding(16).plainRow()
                }
                if feed.items.isEmpty {
                    if feed.loading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 120).plainRow()
                    } else {
                        VStack(spacing: 12) {
                            Text(
                                graph.accounts.accounts.contains {
                                    selection.platform == nil || $0.platform == selection.platform
                                } ? "暂时没有动态，下拉刷新试试" : "登录后查看\(selection.label)信息流")
                            Button("添加账号") { graph.router.showingLogin = true }
                        }.frame(maxWidth: .infinity).padding(.top, 100).plainRow()
                    }
                }
                ForEach(feed.items) { item in
                    Group {
                        switch item {
                        case .weibo(_, let status):
                            if let context = graph.forAccount(item.owner) {
                                StatusCard(status: status, actions: context.statusActions).environment(
                                    context)
                            }
                        case .x(_, let post): XPostCard(post: post, owner: item.owner)
                        }
                    }.feedWidth(in: width).statusRow()
                }
                if feed.hasMore {
                    LoadMoreFooter(
                        list: PagedState(items: feed.items, nextCursor: "more", loadingMore: feed.loading)
                    ) {
                        feed.loadMore()
                    }.plainRow()
                }
            }
            .listStyle(.plain).appListStyle().loadsMoreAsScrolled()
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                width = $0
            }
            .refreshable { await refresh() }
            .pullToRefresh(pull)
            .tabBarHidesOnScroll()
            .onScrollGeometryChange(for: Bool.self) {
                $0.contentOffset.y <= -$0.contentInsets.top + 4
            } action: { _, value in
                atTop = value
            }
            .onChange(of: graph.router.reselects[.home]) {
                if atTop {
                    if !pull.begin() { Task { await refresh() } }
                } else if let first = feed.items.first {
                    withAnimation { proxy.scrollTo(first.id, anchor: .top) }
                }
            }
            .onChange(of: feed.items.first?.id) {
                if atTop, let first = feed.items.first { proxy.scrollTo(first.id, anchor: .top) }
            }
            .onChange(of: selection) {
                if let first = feed.items.first { proxy.scrollTo(first.id, anchor: .top) }
            }
        }
        .task(id: fingerprint) { feed.select(selection) }
    }
    private func refresh() async {
        graph.unread.requestCheck(minInterval: unreadRecheckInterval)
        graph.socialFeed.refresh()
        await graph.socialFeed.waitForIdle()
    }
}
