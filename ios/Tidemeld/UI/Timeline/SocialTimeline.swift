import SwiftUI

struct SocialTimeline: View {
    @Environment(AppGraph.self) private var graph
    @State private var width: CGFloat = 0
    @State private var atTop = true
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
                    let account = graph.accounts.find(item.owner)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(account?.platform.label ?? "") · \(account?.name ?? "")")
                            .font(.caption2).foregroundStyle(AppTheme.accent).padding(.leading, 16).padding(
                                .top, 12)
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
            .refreshable {
                refresh()
                await feed.waitForIdle()
            }
            .tabBarHidesOnScroll()
            .onScrollGeometryChange(for: Bool.self) {
                $0.contentOffset.y <= -$0.contentInsets.top + 4
            } action: { _, value in
                atTop = value
            }
            .onChange(of: graph.router.reselects[.home]) {
                if atTop {
                    refresh()
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
    private func refresh() {
        graph.unread.requestCheck(minInterval: unreadRecheckInterval)
        graph.socialFeed.refresh()
    }
}

private struct XPostCard: View {
    let post: XPost
    let owner: String
    @Environment(AppGraph.self) private var graph
    @Environment(\.displayScale) private var scale
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let name = post.repostedBy {
                Text("\(name) 转发").font(.caption).foregroundStyle(AppTheme.secondary)
            }
            HStack(spacing: 10) {
                if let avatar = post.avatar {
                    WeiboImage(url: avatar, maxPixels: 40 * scale).frame(width: 40, height: 40).clipShape(
                        Circle())
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(post.author).font(.headline)
                    Text("@\(post.handle)" + (post.createdAt.map { " · \(formatPostTime($0))" } ?? ""))
                        .font(.caption).foregroundStyle(AppTheme.secondary)
                }
                Spacer()
                if post.promoted { Text("广告").font(.caption) }
            }
            Text(post.text).font(.body).textSelection(.enabled)
            if !post.pictures.isEmpty {
                PicGrid(items: post.pictures.map { .pic($0) }) { index in
                    graph.router.viewer = ViewerRequest(pics: post.pictures, index: index)
                }
            }
            if let cover = post.videoCover {
                Button {
                    open()
                } label: {
                    WeiboImage(url: cover, maxPixels: 700).frame(height: 200).clipped()
                        .overlay {
                            Image(systemName: "play.circle.fill").font(.largeTitle).foregroundStyle(.white)
                        }
                }.buttonStyle(.plain).accessibilityLabel("在 X 中播放视频")
            }
            if let quote = post.quote {
                Button {
                    graph.router.push(.accountWeb(owner, quote.url))
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(quote.author).font(.headline)
                        Text(quote.text).font(.body)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }
            Button("在 X 中查看与互动") { open() }.buttonStyle(.borderless)
        }
        .padding(16)
        .contentShape(Rectangle())
        .onTapGesture { open() }
    }
    private func open() { graph.router.push(.accountWeb(owner, post.url)) }
}
