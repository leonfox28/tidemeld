import Observation
import SwiftUI

@MainActor @Observable final class XDetailModel {
    var post: XPost?
    var ancestors: [XPost] = []
    var replies: PagedList<XPost>?
    private var contextGeneration = 0
    init(initial: XPost?) { post = initial }
    func start(_ interactions: XInteractions, owner: String, id: String) {
        guard replies == nil else { return }
        let list = PagedList<XPost>(
            fetch: { [weak self] cursor in
                if cursor == nil { self?.contextGeneration += 1 }
                let ticket = self?.contextGeneration
                let page = try await interactions.conversation(owner, id: id, cursor: cursor)
                try Task.checkCancellation()
                // Comment pagination must not replace context or reset the user's position.
                if cursor == nil, ticket == self?.contextGeneration {
                    self?.ancestors = page.ancestors
                    if var post = page.post {
                        post.repostedBy = self?.post?.repostedBy ?? post.repostedBy
                        self?.post = post
                    }
                }
                return page.replies
            }, id: \.originalID)
        replies = list
        list.start()
    }
}

struct XDetailPage: View {
    let owner: String
    let id: String
    @Environment(AppGraph.self) private var graph
    @State private var model: XDetailModel
    @State private var showingReply = false
    init(owner: String, id: String, initial: XPost?) {
        self.owner = owner
        self.id = id
        _model = State(wrappedValue: XDetailModel(initial: initial))
    }
    var body: some View {
        Group {
            if let post = model.post {
                XPostActionHost(post: post, owner: owner, onReply: { showingReply = true }) {
                    actions in
                    layout(actions: actions)
                }
            } else {
                layout(actions: nil)
            }
        }.navigationTitle("帖子").navigationBarTitleDisplayMode(.inline).toolbar(
            .hidden, for: .tabBar
        )
        .task { model.start(graph.xInteractions, owner: owner, id: id) }
        .sheet(isPresented: $showingReply) {
            if let post = model.post {
                XComposer(owner: owner, post: post, onSent: { model.replies?.reload() })
            }
        }
    }
    private func layout(actions: PostInteractionActions?) -> some View {
        PostDetailLayout(
            actions: actions, refresh: { try await model.replies?.refresh() },
            initialFocus: model.ancestors.isEmpty ? nil : "focal:\(id)",
            post: {
                ForEach(model.ancestors, id: \.originalID) { ancestor in
                    PostConversationContext {
                        XPostCard(post: ancestor, owner: owner)
                    }.readingWidth().plainRow().id("ancestor:\(ancestor.originalID)")
                }
                if let post = model.post {
                    XPostCard(post: post, owner: owner, detail: true, showReplyContext: model.ancestors.isEmpty)
                        .readingWidth().plainRow().detailFocus("focal:\(id)")
                }
            },
            responseHeader: {
                PostResponseHeader(
                    tabs: [
                        PostResponseTab(id: "comments", label: "评论", count: actions?.comments ?? 0)
                    ], selected: "comments", likes: actions?.likes ?? 0, select: { _ in }, order: {}
                )
            },
            responses: {
                if let replies = model.replies {
                    PagedRows(list: replies, emptyText: "还没有评论", include: { $0.replyTo == id }) { post in
                        XCommentTile(
                            post: post, owner: owner, authorHandle: model.post?.handle,
                            preview: replies.items.filter { $0.replyTo == post.originalID },
                            onSent: { replies.reload() }
                        ).readingWidth().responseRow()
                    }
                }
            })
    }
}
