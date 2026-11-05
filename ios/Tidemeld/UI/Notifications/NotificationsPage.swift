import Observation
import SwiftUI

/// The notification lists, each made when its tab is first shown and kept while
/// the app runs. Another account, or none, starts them over.
@MainActor @Observable
final class NotificationsModel {
    @ObservationIgnored private var api: WeiboAPI?
    @ObservationIgnored private(set) var comments: PagedList<CommentNotice>?
    @ObservationIgnored private(set) var mentionComments: PagedList<CommentNotice>?
    @ObservationIgnored private(set) var mentionStatuses: PagedList<Status>?
    @ObservationIgnored private(set) var likes: PagedList<LikeNotice>?

    /// Gives the model what it loads with; before the lists first draw.
    func attach(_ api: WeiboAPI, session: SessionController) {
        guard self.api == nil else { return }
        self.api = api
        session.onUidChange { [weak self] _ in self?.forget() }
    }

    /// Drops the lists, so the next account's are made and loaded afresh as
    /// their tabs are shown.
    private func forget() {
        comments = nil
        mentionComments = nil
        mentionStatuses = nil
        likes = nil
    }

    func commentList(_ kind: NoticeKind) -> PagedList<CommentNotice> {
        let api = api!
        if kind == .comments {
            if let comments { return comments }
            let list = PagedList<CommentNotice>(fetch: { try await api.fetchCommentNotices(maxId: $0) }, id: \.id)
            comments = list
            return list
        }
        if let mentionComments { return mentionComments }
        let list = PagedList<CommentNotice>(fetch: { try await api.fetchMentionComments(maxId: $0) }, id: \.id)
        mentionComments = list
        return list
    }

    func statusList() -> PagedList<Status> {
        if let mentionStatuses { return mentionStatuses }
        let api = api!
        let list = PagedList<Status>(fetch: { try await api.fetchMentionStatuses(maxId: $0) }, id: \.id)
        mentionStatuses = list
        return list
    }

    func likeList() -> PagedList<LikeNotice> {
        if let likes { return likes }
        let api = api!
        let list = PagedList<LikeNotice>(fetch: { try await api.fetchLikeNotices(maxId: $0) }, id: \.id)
        likes = list
        return list
    }

    /// Whether [kind]'s list has loaded, so a mark on it means newer news.
    func loaded(_ kind: NoticeKind) -> Bool {
        switch kind {
        case .comments: comments?.state.list != nil
        case .mentionComments: mentionComments?.state.list != nil
        case .mentionStatuses: mentionStatuses?.state.list != nil
        case .likes: likes?.state.list != nil
        }
    }

    func refresh(_ kind: NoticeKind) async throws {
        switch kind {
        case .comments, .mentionComments: try await commentList(kind).refresh()
        case .mentionStatuses: try await statusList().refresh()
        case .likes: try await likeList().refresh()
        }
    }
}

/// The notifications tab: comments, mentions and likes, one list each.
///
/// A list loads when its tab is first shown, which marks its kind read on
/// Weibo's side. Opening a tab marked unread clears the mark, and reloads the
/// list if it was loaded before.
struct NotificationsPage: View {
    @Environment(AppGraph.self) private var graph
    @State private var model = NotificationsModel()
    @State private var kind: NoticeKind = .comments
    /// The tab bar's, as the list shown scrolls; one for the page, as the
    /// lists side by side would each set it.
    @State private var tabBarVisible = true
    /// Whether the list shown is at its top, with nothing under the top bar.
    @State private var atTop = true
    /// How far the bars reach over the lists; see [notices].
    @State private var barInsets = EdgeInsets()
    @State private var width: CGFloat = 0

    var body: some View {
        Group {
            switch graph.session.state {
            case .signedOut(let expired): LoginPrompt(expired: expired)
            case .signedIn(let account): notices.id(account.uid)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
        .navigationTitle("通知")
        .toolbarTitleDisplayMode(.inline)
        .tabBarVisible(tabBarVisible)
    }

    private var notices: some View {
        let _ = model.attach(graph.api, session: graph.session)
        return GeometryReader { screen in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(NoticeKind.allCases, id: \.self) { kind in
                        NoticeList(
                            model: model, kind: kind, shown: self.kind == kind, tabBarVisible: $tabBarVisible,
                            atTop: $atTop, barInsets: barInsets
                        )
                        .frame(width: screen.size.width, height: screen.size.height)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            // The page more than half in view, as the Android app's pager has it.
            .scrollPosition(id: Binding(get: { kind }, set: { if let page = $0 { kind = page } }), anchor: .center)
            .scrollIndicators(.hidden)
            // The bars blur what goes under them, as elsewhere. The lists'
            // own edge effects don't show, so this scroll view's does; and as
            // its content is always under the top bar, only once the list
            // shown has gone under it, else it would fade the first row.
            .scrollEdgeEffectStyle(.soft, for: .all)
            .scrollEdgeEffectHidden(atTop, for: .top)
        }
        // The lists scroll on under the bars, as elsewhere, keeping clear of
        // them themselves. (A paged `TabView` kept its pages between the bars,
        // and the lists, made as tall as the screen, came out centred on that,
        // a little way down.)
        .ignoresSafeArea(.container, edges: .vertical)
        .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { barInsets = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // In the navigation bar, in place of the title, which the tab bar
        // already gives: under it, they made the top bar twice as tall. The
        // bar gives them only what they need unless told how wide to be: the
        // page's width within its margins, but no wider than a phone's, as
        // across a wide window they would drift apart.
        .toolbar {
            ToolbarItem(placement: .principal) {
                KindBar(kind: $kind).frame(width: min(max(width - 32, 0), 400))
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .onChange(of: kind) { withAnimation(.snappy(duration: 0.3)) { tabBarVisible = true } }
        // The user is looking at the open tab: clear its mark, and reload its
        // list if that came before whatever is new. The reload goes on in a
        // task of its own: clearing the mark changes this task's id, which
        // cancels it, and would cancel the request along with it.
        .task(id: "\(kind)\(graph.unread.state.has(kind))") {
            guard graph.unread.state.has(kind) else { return }
            graph.unread.markRead(kind)
            if model.loaded(kind) {
                let kind = kind
                Task { try? await model.refresh(kind) }
            }
        }
    }
}

/// The kinds, as tabs spread across the bar, each taking taps a little way
/// either side of its label: the open one in the accent colour over a line,
/// which moves along as the open tab changes; one with something unread has a
/// dot. Even shares of the width would leave the two long labels all but
/// touching.
private struct KindBar: View {
    @Binding var kind: NoticeKind
    @Environment(AppGraph.self) private var graph
    @Namespace private var line

    var body: some View {
        HStack(spacing: 0) {
            ForEach(NoticeKind.allCases) { each in
                if each != NoticeKind.allCases.first { Spacer(minLength: 0) }
                let open = kind == each
                let unread = graph.unread.state.has(each)
                Button {
                    withAnimation(.snappy) { kind = each }
                } label: {
                    Text(each.label)
                        .font(.body.weight(open ? .semibold : .regular))
                        .foregroundStyle(open ? AppTheme.accent : AppTheme.secondary)
                        .lineLimit(1)
                        .overlay(alignment: .topTrailing) {
                            if unread {
                                Circle().fill(.red).frame(width: 6, height: 6).offset(x: 8, y: -2)
                            }
                        }
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            if open {
                                Capsule()
                                    .fill(AppTheme.accent)
                                    .frame(width: 20, height: 3)
                                    .matchedGeometryEffect(id: "line", in: line)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(minWidth: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(unread ? "\(each.label)，有未读" : each.label)
                .accessibilityAddTraits(open ? .isSelected : [])
            }
        }
        // A swipe changes the open tab too.
        .animation(.snappy, value: kind)
        // As the system's own bars, it doesn't grow with the text size, which
        // would take it past the bar's width.
        .dynamicTypeSize(...DynamicTypeSize.large)
    }
}

/// One kind's list, with its own scrolling and pull to refresh.
private struct NoticeList: View {
    let model: NotificationsModel
    let kind: NoticeKind
    /// Whether it is the list shown, as only that one may load: loading a list
    /// marks its kind read on Weibo's side.
    let shown: Bool
    let tabBarVisible: Binding<Bool>
    let atTop: Binding<Bool>
    let barInsets: EdgeInsets
    @Environment(AppGraph.self) private var graph
    @State private var top = true
    @State private var pull = PullToRefresh()

    var body: some View {
        ScrollViewReader { proxy in
            list
                // Tapping the open tab again: back to the top, or from there a
                // refresh, shown as on a pull. Only the list shown answers it.
                .onChange(of: graph.router.reselects[.notifications]) {
                    guard shown else { return }
                    if top {
                        if !pull.begin() { Task { await refresh() } }
                    } else if let first = firstID {
                        withAnimation { proxy.scrollTo(first, anchor: .top) }
                    }
                }
        }
    }

    private var list: some View {
        List {
            switch kind {
            case .comments, .mentionComments:
                PagedRows(
                    list: model.commentList(kind), emptyText: kind == .comments ? "还没有收到评论" : "还没有评论提到你"
                ) { notice in
                    CommentNoticeTile(notice: notice).readingWidth().responseRow()
                }
            case .mentionStatuses:
                PagedRows(list: model.statusList(), emptyText: "还没有微博提到你") { status in
                    StatusCard(status: status, actions: graph.statusActions).readingWidth().statusRow()
                }
            case .likes:
                PagedRows(list: model.likeList(), emptyText: "还没有收到赞") { notice in
                    LikeNoticeTile(notice: notice).readingWidth().responseRow()
                }
            }
        }
        .listStyle(.plain)
        .appListStyle()
        .loadsMoreAsScrolled()
        .safeAreaPadding(.top, barInsets.top)
        .safeAreaPadding(.bottom, barInsets.bottom)
        .modifier(HideOnScroll(visible: shown ? tabBarVisible : .constant(true), tabBar: true))
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y <= -$0.contentInsets.top + 1 } action: { _, top in
            self.top = top
            if shown { atTop.wrappedValue = top }
        }
        .onChange(of: shown) { if shown { atTop.wrappedValue = top } }
        .refreshable { await refresh() }
        .pullToRefresh(pull)
        .task(id: shown) {
            if shown { start() }
        }
    }

    private func refresh() async {
        do {
            try await model.refresh(kind)
        } catch {
            graph.toasts.showError(error, router: graph.router)
        }
    }

    /// The first row's id, to scroll back to.
    private var firstID: String? {
        switch kind {
        case .comments, .mentionComments: model.commentList(kind).items.first?.id
        case .mentionStatuses: model.statusList().items.first?.id
        case .likes: model.likeList().items.first?.id
        }
    }

    // Each list loads when its tab is first shown.
    private func start() {
        switch kind {
        case .comments, .mentionComments: model.commentList(kind).start()
        case .mentionStatuses: model.statusList().start()
        case .likes: model.likeList().start()
        }
    }
}

/// A comment to the user, above the comment it answers (if any) and the post it
/// is on. Tapping it opens the post.
private struct CommentNoticeTile: View {
    let notice: CommentNotice
    @Environment(AppGraph.self) private var graph

    var body: some View {
        let actions = graph.statusActions
        let status = notice.status
        let open: (() -> Void)? = status?.user == nil ? nil : { actions.onOpen?(status!) }
        CommentTile(comment: notice.comment, actions: actions, onTap: open) {
            VStack(alignment: .leading, spacing: 6) {
                if let replyTo = notice.replyTo { CommentQuote(comment: replyTo) }
                if let status { StatusQuote(status: status, onTap: open) }
            }
        }
    }
}

/// Who liked what, and when. Tapping it opens the post.
private struct LikeNoticeTile: View {
    let notice: LikeNotice
    @Environment(AppGraph.self) private var graph

    var body: some View {
        let actions = graph.statusActions
        let status = notice.status
        let open: (() -> Void)? =
            if let status, status.user != nil {
                notice.statusComplete
                    ? { actions.onOpen?(status) }
                    // A cut-down post would show without its pictures and
                    // counts until the detail page has loaded it.
                    : { graph.router.push(.status(id: status.id, initial: nil)) }
            } else { nil }
        HStack(alignment: .top, spacing: 10) {
            UserAvatar(user: notice.user, size: 32, onTap: actions.onUser)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        "\(Text(notice.user?.screenName ?? "微博用户").fontWeight(.medium).foregroundStyle(AppTheme.secondary))\(notice.comment != nil ? " 赞了你的评论" : " 赞了你的微博")"
                    )
                    .font(.subheadline)
                    .lineLimit(1)
                    if let time = notice.createdAt {
                        Text(formatPostTime(time)).font(.caption).foregroundStyle(AppTheme.secondary)
                    }
                }
                if let comment = notice.comment { CommentQuote(comment: comment) }
                if let status { StatusQuote(status: status, onTap: open) }
            }
        }
        .foregroundStyle(AppTheme.foreground)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { open?() }
    }
}

/// A comment cited in a notification: its author and the start of its text.
private struct CommentQuote: View {
    let comment: Comment

    var body: some View {
        let name = comment.user.map { "\($0.screenName)：" } ?? ""
        Text("\(Text(name).fontWeight(.medium))\(plainStatusText(comment.text))")
            .font(.caption)
            .foregroundStyle(AppTheme.secondary)
            .lineLimit(2)
            .padding(.leading, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                Rectangle().fill(AppTheme.outline).frame(width: 2)
            }
    }
}

/// The post a notification is about, as a small card: a picture, its author and
/// its text.
private struct StatusQuote: View {
    let status: Status
    let onTap: (() -> Void)?
    @Environment(AppGraph.self) private var graph
    @Environment(\.displayScale) private var scale

    var body: some View {
        let quality = graph.settings.settings.imageQuality
        let thumb = status.pics.first?.variant(for: quality.listPixels(48, scale: scale)).url ?? status.video?.coverURL
        HStack(spacing: 8) {
            if let thumb {
                WeiboImage(url: thumb, maxPixels: 48 * scale)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            // Deleted or hidden posts come without an author.
            Group {
                if let user = status.user {
                    Text("\(Text("@\(user.screenName)：").fontWeight(.medium))\(plainStatusText(status.text))")
                } else {
                    Text("这条微博已被删除或不可见")
                }
            }
            .font(.caption)
            .foregroundStyle(AppTheme.secondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(AppTheme.elevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { onTap?() }
    }
}
