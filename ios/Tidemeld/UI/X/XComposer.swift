import SwiftUI

struct XComposer: View {
    let owner: String
    let post: XPost
    var quote = false
    var onSent: (() -> Void)? = nil
    @Environment(AppGraph.self) private var graph
    @State private var draftKey: String?
    var body: some View {
        let key =
            draftKey ?? graph.xInteractions.key(owner, post.originalID)
            + (quote ? ":quote" : ":reply")
        PostComposer(
            request: PostComposerRequest(
                title: quote ? "引用转发" : "写评论", hint: quote ? "引用转发…" : "回复 @\(post.handle)",
                drafts: graph.xInteractions.drafts, draftKey: key,
                send: { text, _ in
                    try await graph.xInteractions.write(
                        owner, post: post, action: quote ? .quote : .reply, text: text)
                    onSent?()
                }, sentMessage: "发送成功", context: "使用 X · \(graph.accounts.find(owner)?.name ?? "")")
        )
        .onAppear { if draftKey == nil { draftKey = key } }
    }
}
