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
        List {
            if let post = model.post {
                XPostCard(post: post, owner: owner, onReply: { showingReply = true }).readingWidth()
                    .statusRow()
            }
            Text("评论").font(.headline).padding(16).readingWidth().plainRow()
            if let replies = model.replies {
                PagedRows(list: replies, emptyText: "还没有评论") { post in
                    XPostCard(post: post, owner: owner).readingWidth().statusRow()
                }
            }
        }.listStyle(.plain).appListStyle().loadsMoreAsScrolled()
            .navigationTitle("帖子").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("刷新") { model.replies?.reload() } }
            }
            .safeAreaInset(edge: .bottom) {
                if model.post != nil {
                    Button("写评论…") { showingReply = true }.frame(maxWidth: .infinity, minHeight: 48)
                        .background(.bar)
                }
            }
            .refreshable {
                do { try await model.replies?.refresh() } catch {
                    graph.toasts.showError(error, router: graph.router)
                }
            }
            .task { model.start(graph.xInteractions, owner: owner, id: id) }
            .sheet(isPresented: $showingReply) {
                if let post = model.post {
                    XComposer(owner: owner, post: post, onSent: { model.replies?.reload() })
                }
            }
    }
}
