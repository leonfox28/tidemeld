import Observation
import SwiftUI

/// The notification lists, each made when its tab is first shown and kept while
/// the app runs.
@MainActor @Observable
final class NotificationsModel {
    @ObservationIgnored private var api: WeiboAPI?
    @ObservationIgnored private(set) var comments: PagedList<CommentNotice>?
    @ObservationIgnored private(set) var mentionComments: PagedList<CommentNotice>?
    @ObservationIgnored private(set) var mentionStatuses: PagedList<Status>?
    @ObservationIgnored private(set) var likes: PagedList<LikeNotice>?

    /// Gives the model what it loads with; before the lists first draw.
    func attach(_ api: WeiboAPI) {
        if self.api == nil { self.api = api }
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
    }

    private var notices: some View {
        let _ = model.attach(graph.api)
        return TabView(selection: $kind) {
            ForEach(NoticeKind.allCases) { kind in
                NoticeList(model: model, kind: kind, shown: self.kind == kind).tag(kind)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .safeAreaBar(edge: .top) { KindBar(kind: $kind) }
        // The user is looking at the open tab: clear its mark, and reload its
        // list if that came before whatever is new.
        .task(id: "\(kind)\(graph.unread.state.has(kind))") {
            guard graph.unread.state.has(kind) else { return }
            graph.unread.markRead(kind)
            if model.loaded(kind) { try? await model.refresh(kind) }
        }
    }
}

/// The kinds, as glass buttons; one with something unread has a dot.
private struct KindBar: View {
    @Binding var kind: NoticeKind
    @Environment(AppGraph.self) private var graph

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(NoticeKind.allCases) { each in
                    let unread = graph.unread.state.has(each)
                    Button {
                        withAnimation(.snappy) { kind = each }
                    } label: {
                        Text(each.label)
                            .font(.subheadline.weight(kind == each ? .semibold : .regular))
                            .lineLimit(1)
                            .overlay(alignment: .topTrailing) {
                                if unread {
                                    Circle().fill(.red).frame(width: 6, height: 6).offset(x: 8, y: -2)
                                }
                            }
                    }
                    .buttonStyle(.glass(kind == each ? .regular.tint(AppTheme.primary.opacity(0.35)) : .regular))
                    .accessibilityLabel(unread ? "\(each.label)，有未读" : each.label)
                    .accessibilityAddTraits(kind == each ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity)
    }
}

/// One kind's list, with its own scrolling and pull to refresh.
private struct NoticeList: View {
    let model: NotificationsModel
    let kind: NoticeKind
    /// Whether it is the list shown, as only that one may load: loading a list
    /// marks its kind read on Weibo's side.
    let shown: Bool
    @Environment(AppGraph.self) private var graph

    var body: some View {
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
        .refreshable {
            do {
                try await model.refresh(kind)
            } catch {
                graph.toasts.showError(error, router: graph.router)
            }
        }
        .task(id: shown) {
            if shown { start() }
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
