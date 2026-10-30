import Observation
import SwiftUI

enum DetailTab: Hashable {
    case reposts, comments
}

/// What a status's page holds while it is open: the full status, and the lists
/// of comments and reposts opened so far, which stay loaded, so going back to
/// one doesn't fetch it again.
///
/// Opening the page loads the status and its first page of comments; the
/// reposts load only when their tab is opened (PLAN §2).
@MainActor @Observable
final class StatusDetailModel {
    let id: String
    private(set) var status: Status?
    private(set) var error: WeiboError?
    var tab: DetailTab = .comments
    var order: CommentOrder = .hot

    /// What the user is writing here, by what it replies to.
    @ObservationIgnored let drafts = CommentDrafts()
    /// Comments being deleted, so a second tap doesn't ask Weibo again.
    @ObservationIgnored var deleting: Set<String> = []

    /// Comments the user added here, less those they deleted, and their
    /// reposts, since the status they were counted on loaded: newer data
    /// already has them.
    private var added: (generation: Int, comments: Int, reposts: Int)?
    private var generation = 0

    @ObservationIgnored private var comments: [CommentOrder: PagedList<Comment>] = [:]
    @ObservationIgnored private var reposts: PagedList<Status>?
    @ObservationIgnored private var graph: AppGraph?
    @ObservationIgnored private var started = false

    init(id: String) { self.id = id }

    /// Gives the model what it loads with; before the page first draws, which
    /// asks for the comments.
    func attach(_ graph: AppGraph) {
        if self.graph == nil { self.graph = graph }
    }

    func start() {
        guard !started else { return }
        started = true
        reload()
    }

    func reload() {
        error = nil
        Task {
            do {
                loaded(try await graph!.api.fetchStatus(id))
            } catch {
                self.error = WeiboError.of(error)
            }
        }
    }

    private func loaded(_ status: Status) {
        self.status = status
        generation += 1
        error = nil
    }

    func commentsCount(_ status: Status) -> Int {
        max(0, status.commentsCount + (counted(status)?.comments ?? 0))
    }

    func repostsCount(_ status: Status) -> Int { status.repostsCount + (counted(status)?.reposts ?? 0) }

    private func counted(_ status: Status) -> (generation: Int, comments: Int, reposts: Int)? {
        guard let added, added.generation == generation else { return nil }
        return added
    }

    /// Counts [comments] and [reposts] the user added (or deleted, if
    /// negative).
    func count(comments: Int = 0, reposts: Int = 0) {
        let before = added?.generation == generation ? added : nil
        added = (generation, (before?.comments ?? 0) + comments, (before?.reposts ?? 0) + reposts)
    }

    /// The comments on [status] in [order], loading their first page if they
    /// weren't open.
    func comments(_ status: Status, authorId: String, order: CommentOrder) -> PagedList<Comment> {
        if let list = comments[order] { return list }
        let api = graph!.api
        let list = PagedList<Comment>(
            fetch: { try await api.fetchComments(statusId: status.id, authorId: authorId, order: order, maxId: $0) },
            id: \.id)
        comments[order] = list
        graph!.openLists.comments.add(status.id, list)
        // Not while the page is being drawn, which asked for it.
        Task { list.start() }
        return list
    }

    func reposts(_ status: Status) -> PagedList<Status> {
        if let reposts { return reposts }
        let api = graph!.api
        let list = PagedList<Status>(
            fetch: { try await api.fetchReposts(statusId: status.id, page: $0.flatMap(Int.init) ?? 1) },
            id: \.id)
        reposts = list
        graph!.openLists.reposts.add(status.id, list)
        // Not while the page is being drawn, which asked for it.
        Task { list.start() }
        return list
    }

    /// Loads the status and the list on show again; throws on failure, what was
    /// shown staying, for the caller to report.
    func refresh(_ status: Status) async throws {
        let api = graph!.api
        async let fetched = api.fetchStatus(id)
        if tab == .reposts {
            try await reposts(status).refresh()
        } else if let authorId = status.user?.id {
            try await comments(status, authorId: authorId, order: order).refresh()
        }
        loaded(try await fetched)
    }
}

/// A status with its full text, and its comments and reposts.
///
/// [initial] (the status as the previous page showed it) shows until the full
/// one arrives.
struct StatusDetailPage: View {
    let id: String
    let initial: Status?

    @Environment(AppGraph.self) private var graph
    @State private var model: StatusDetailModel

    init(id: String, initial: Status?) {
        self.id = id
        self.initial = initial
        _model = State(wrappedValue: StatusDetailModel(id: id))
    }

    var body: some View {
        let _ = model.attach(graph)
        Group {
            if let status = model.status ?? initial {
                StatusDetail(model: model, status: status)
            } else if let error = model.error {
                ErrorRetry(error: error) { model.reload() }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
        .navigationTitle("微博正文")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { model.start() }
    }
}

private struct StatusDetail: View {
    let model: StatusDetailModel
    let status: Status

    @Environment(AppGraph.self) private var graph
    @State private var commentToDelete: Comment?
    @State private var actionsVisible = true

    var body: some View {
        @Bindable var model = model
        let authorId = status.user?.id
        let comments = authorId.map { model.comments(status, authorId: $0, order: model.order) }
        List {
            StatusCard(status: status, actions: cardActions, detail: true)
                .readingWidth()
                .plainRow()
            if model.status == nil, let error = model.error {
                HStack {
                    Text("正文加载失败：\(error.message)").font(.footnote)
                    Spacer()
                    Button("重试") { model.reload() }.font(.footnote)
                }
                .foregroundStyle(AppTheme.error)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppTheme.errorContainer)
                .plainRow()
            }
            Section {
                if model.tab == .reposts {
                    PagedRows(list: model.reposts(status), emptyText: "还没有人转发") { repost in
                        RepostTile(status: repost, actions: graph.statusActions).readingWidth().responseRow()
                    }
                } else if let comments, let authorId {
                    PagedRows(list: comments, emptyText: "还没有评论") { comment in
                        CommentTile(
                            comment: comment, authorId: authorId, actions: graph.statusActions,
                            onThread: {
                                graph.router.push(
                                    .comments(CommentThread(root: comment, statusId: status.id, statusAuthorId: authorId)))
                            },
                            onTap: comment.canReply ? { reply(comment) } : nil,
                            onDelete: comment.user?.id == graph.session.state.uid && graph.session.state.uid != nil
                                ? { commentToDelete = comment } : nil
                        )
                        .readingWidth()
                        .responseRow()
                    }
                } else {
                    Text("无法加载这条微博的评论")
                        .foregroundStyle(AppTheme.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(40)
                        .plainRow()
                }
            } header: {
                DetailTabs(model: model, status: status).readingWidth().listHeader()
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .appListStyle()
        .refreshable {
            do {
                try await model.refresh(status)
            } catch {
                graph.toasts.showError(error, router: graph.router)
            }
        }
        .toolbar {
            if status.user != nil { actions }
        }
        .bottomBarHidesOnScroll($actionsVisible)
        .confirmationDialog(
            "确定删除这条评论吗？", isPresented: deletingComment, titleVisibility: .visible,
            presenting: commentToDelete
        ) { comment in
            Button("删除", role: .destructive) { delete(comment) }
        }
    }

    private var deletingComment: Binding<Bool> {
        Binding(get: { commentToDelete != nil }, set: { if !$0 { commentToDelete = nil } })
    }

    private var cardActions: StatusCardActions {
        var actions = graph.statusActions
        let base = actions
        let id = status.id
        // Its own "展开" stays inert: the full text is shown or on its way.
        actions.onExpand = { if $0.id != id { base.onExpand?($0) } }
        // The page has nothing left to show once deleted.
        actions.onDelete = { [graph] deleted in
            graph.delete(deleted) {
                if case .status(let shown, _)? = graph.router.paths[graph.router.tab]?.last, shown == id {
                    graph.router.pop()
                }
            }
        }
        return actions
    }

    /// Comment, repost and like, as one group at the right of the bottom
    /// toolbar; the counts are on the tabs above the list, but for likes.
    @ToolbarContentBuilder
    private var actions: some ToolbarContent {
        let target = LikeTarget(kind: .status, id: status.id)
        let shown = graph.likes.shown(target, loaded: status.like)
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItemGroup(placement: .bottomBar) {
            Button("写评论", systemImage: "square.and.pencil") { comment() }
            // The list of reposts, if open, gets the new one from the repost itself.
            Button("转发", systemImage: "arrow.2.squarepath") {
                graph.repost(status) { model.count(reposts: 1) }
            }
            Button {
                if !shown.pending { graph.toggleLike(target, loaded: status.like) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: shown.like.liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                    if shown.like.count > 0 { Text(formatCount(shown.like.count)).monospacedDigit() }
                }
            }
            .tint(shown.like.liked ? AppTheme.primary : nil)
            .accessibilityLabel(shown.like.count > 0 ? "赞 \(shown.like.count)" : "赞")
            .sensoryFeedback(.selection, trigger: shown.like.liked)
        }
    }

    private func editComments(_ edit: (PagedList<Comment>) -> Void) {
        graph.openLists.comments.forEach(status.id, edit)
    }

    private func comment() {
        let api = graph.api
        let statusId = status.id
        graph.router.commentComposer = CommentComposerRequest(
            statusId: statusId, title: "写评论", hint: "写评论…", drafts: model.drafts, draftKey: "status",
            send: { text, pid in
                let comment = try await api.postComment(statusId: statusId, text: text, pid: pid)
                model.count(comments: 1)
                model.tab = .comments
                if let comment { editComments { $0.prepend(comment) } }
            },
            sentMessage: "评论成功")
    }

    private func reply(_ target: Comment) {
        let api = graph.api
        let statusId = status.id
        let name = target.user?.screenName
        graph.router.commentComposer = CommentComposerRequest(
            statusId: statusId, title: name.map { "回复 @\($0)" } ?? "回复评论",
            hint: name.map { "回复 @\($0)" } ?? "回复评论…", drafts: model.drafts, draftKey: target.id,
            send: { text, pid in
                let reply = try await api.postComment(statusId: statusId, text: text, replyTo: target.id, pid: pid)
                // Weibo counts replies among a status's comments.
                model.count(comments: 1)
                editComments { list in list.replace(target.id) { $0.withReply(reply) } }
            },
            sentMessage: "回复成功")
    }

    private func delete(_ comment: Comment) {
        guard model.deleting.insert(comment.id).inserted else { return }
        Task {
            defer { model.deleting.remove(comment.id) }
            do {
                try await graph.api.deleteComment(comment.id)
                model.count(comments: -1)
                editComments { $0.remove(comment.id) }
                graph.toasts.show("已删除")
            } catch {
                graph.toasts.showError(error, router: graph.router)
            }
        }
    }
}

/// The repost and comment tabs with their counts (with what the user added or
/// deleted here), the comment order, and the like count.
private struct DetailTabs: View {
    @Bindable var model: StatusDetailModel
    let status: Status
    @Environment(AppGraph.self) private var graph

    var body: some View {
        let like = graph.likes.shown(LikeTarget(kind: .status, id: status.id), loaded: status.like).like
        HStack(spacing: 12) {
            Picker("列表", selection: $model.tab) {
                Text("转发 \(formatCount(model.repostsCount(status)))").tag(DetailTab.reposts)
                Text("评论 \(formatCount(model.commentsCount(status)))").tag(DetailTab.comments)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            if model.tab == .comments {
                Menu {
                    Picker("排序", selection: $model.order) {
                        Text("按热度").tag(CommentOrder.hot)
                        Text("按时间").tag(CommentOrder.time)
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(model.order == .hot ? "按热度" : "按时间")
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .font(.footnote)
                }
            }
            Spacer()
            Text("赞 \(formatCount(like.count))").font(.footnote).foregroundStyle(AppTheme.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// A repost in a status's list of reposts.
struct RepostTile: View {
    let status: Status
    let actions: StatusCardActions

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            UserAvatar(user: status.user, size: 32, onTap: actions.onUser)
            VStack(alignment: .leading, spacing: 4) {
                Text(status.user?.screenName ?? "微博用户")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.secondary)
                    .lineLimit(1)
                StatusText(html: status.text, urls: status.urls, onLink: actions.onLink)
                    .foregroundStyle(AppTheme.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let time = status.createdAt {
                    Text(formatPostTime(time)).font(.caption).foregroundStyle(AppTheme.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { actions.onOpen?(status) }
    }
}

extension View {
    /// A comment or repost as a list row, divided from the next under its text.
    func responseRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(AppTheme.background)
            .listRowSeparatorTint(AppTheme.outline)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 58 }
    }
}
