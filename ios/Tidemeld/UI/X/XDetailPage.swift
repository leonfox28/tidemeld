import Observation
import SwiftUI

@MainActor @Observable final class XDetailModel {
    var post: XPost?
    var replies: PagedList<XPost>?
    init(initial: XPost?) { post = initial }
    func start(_ interactions: XInteractions, owner: String, id: String) {
        guard replies == nil else { return }
        let list = PagedList<XPost>(
            fetch: { [weak self] cursor in
                let page = try await interactions.conversation(owner, id: id, cursor: cursor)
                if let post = page.post { self?.post = post }
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
            post: {
                if let post = model.post {
                    XPostCard(post: post, owner: owner, detail: true).readingWidth().plainRow()
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
                    PagedRows(list: replies, emptyText: "还没有评论") { post in
                        XPostCard(post: post, owner: owner).readingWidth().statusRow()
                    }
                }
            })
    }
}
