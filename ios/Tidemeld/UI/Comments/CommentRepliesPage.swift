import Observation
import SwiftUI

/// The replies of a thread, loaded while its page is open, and what the user
/// writes there.
@MainActor @Observable
final class RepliesModel {
    let thread: CommentThread
    private(set) var replies: PagedList<Comment>?
    /// What the user is writing here, by what it replies to.
    @ObservationIgnored let drafts = CommentDrafts()
    /// Replies being deleted, so a second tap doesn't ask Weibo again.
    @ObservationIgnored var deleting: Set<String> = []

    init(thread: CommentThread) { self.thread = thread }

    func start(_ api: WeiboAPI) {
        guard replies == nil else { return }
        let thread = thread
        let list = PagedList<Comment>(
            fetch: {
                try await api.fetchReplies(commentId: thread.root.id, authorId: thread.statusAuthorId, maxId: $0)
            },
            id: \.id)
        replies = list
        list.start()
    }
}

/// A comment and all the replies in its thread ("楼中楼"), where the user can
/// reply to any of them.
struct CommentRepliesPage: View {
    let thread: CommentThread

    @Environment(AppGraph.self) private var graph
    @State private var model: RepliesModel
    @State private var replyToDelete: Comment?
    @State private var actionsVisible = true

    init(thread: CommentThread) {
        self.thread = thread
        _model = State(wrappedValue: RepliesModel(thread: thread))
    }

    var body: some View {
        let root = thread.root
        let me = graph.session.state.uid
        List {
            CommentTile(
                comment: root, authorId: thread.statusAuthorId, actions: graph.statusActions,
                onTap: root.canReply ? { reply(root) } : nil
            )
            .readingWidth()
            .plainRow()
            if let replies = model.replies {
                Section {
                    PagedRows(list: replies, emptyText: "还没有回复") { item in
                        CommentTile(
                            comment: item, authorId: thread.statusAuthorId, actions: graph.statusActions,
                            onTap: item.canReply ? { reply(item) } : nil,
                            onDelete: me != nil && item.user?.id == me ? { replyToDelete = item } : nil
                        )
                        .readingWidth()
                        .responseRow()
                    }
                } header: {
                    Text("\(replies.state.list?.total ?? root.replyCount) 条回复")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.foreground)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .readingWidth()
                        .listHeader()
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .appListStyle()
        .loadsMoreAsScrolled()
        .refreshable {
            do {
                try await model.replies?.refresh()
            } catch {
                graph.toasts.showError(error, router: graph.router)
            }
        }
        .navigationTitle("评论详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if root.canReply {
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button(root.user.map { "回复 @\($0.screenName)" } ?? "回复评论", systemImage: "arrowshape.turn.up.left") {
                        reply(root)
                    }
                }
            }
        }
        .bottomBarHidesOnScroll($actionsVisible)
        .confirmationDialog(
            "确定删除这条回复吗？", isPresented: deleting, titleVisibility: .visible, presenting: replyToDelete
        ) { reply in
            Button("删除", role: .destructive) { delete(reply) }
        }
        .onAppear { model.start(graph.api) }
    }

    private var deleting: Binding<Bool> {
        Binding(get: { replyToDelete != nil }, set: { if !$0 { replyToDelete = nil } })
    }

    /// Shows a change of the thread on the status page below too.
    private func editRoot(_ change: @escaping (Comment) -> Comment) {
        graph.openLists.comments.forEach(thread.statusId) { $0.replace(thread.root.id, change) }
    }

    private func reply(_ target: Comment) {
        let api = graph.api
        let thread = thread
        let replies = model.replies
        let name = target.user?.screenName
        graph.router.commentComposer = CommentComposerRequest(
            statusId: thread.statusId, title: name.map { "回复 @\($0)" } ?? "回复评论",
            hint: name.map { "回复 @\($0)" } ?? "回复评论…", drafts: model.drafts, draftKey: target.id,
            send: { text, pid in
                let reply = try await api.postComment(
                    statusId: thread.statusId, text: text, replyTo: target.id, pid: pid)
                // Replies list newest first.
                if let reply { replies?.prepend(reply) }
                editRoot { $0.withReply(reply) }
            },
            sentMessage: "回复成功")
    }

    private func delete(_ reply: Comment) {
        guard model.deleting.insert(reply.id).inserted else { return }
        Task {
            defer { model.deleting.remove(reply.id) }
            do {
                try await graph.api.deleteComment(reply.id)
                model.replies?.remove(reply.id)
                editRoot { $0.withoutReply(reply.id) }
                graph.toasts.show("已删除")
            } catch {
                graph.toasts.showError(error, router: graph.router)
            }
        }
    }
}
