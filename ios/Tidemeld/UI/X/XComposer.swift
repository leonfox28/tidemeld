import SwiftUI

struct XComposer: View {
    let owner: String
    let post: XPost
    var quote = false
    var onSent: (() -> Void)? = nil
    @Environment(AppGraph.self) private var graph
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var draftKey: String?
    @State private var sending = false
    @State private var error: String?
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("使用 X · \(graph.accounts.find(owner)?.name ?? "")").font(.subheadline)
                    .foregroundStyle(
                        AppTheme.accent)
                Text("\(quote ? "引用" : "回复") @\(post.handle)").font(.subheadline).foregroundStyle(
                    AppTheme.secondary)
                TextEditor(text: $text).focused($focused).frame(minHeight: 150).disabled(sending)
                    .accessibilityLabel("评论内容")
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                if sending { ProgressView().frame(maxWidth: .infinity) }
            }.padding(16).navigationTitle(quote ? "引用转发" : "写评论").navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(sending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发送", action: send).disabled(
                        sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }.interactiveDismissDisabled(sending)
            .onAppear {
                guard draftKey == nil else { return }
                let key =
                    graph.xInteractions.key(owner, post.originalID) + (quote ? ":quote" : ":reply")
                draftKey = key
                text = graph.xInteractions.drafts[key] ?? ""
                focused = true
            }
            .onChange(of: text) { if let draftKey { graph.xInteractions.drafts[draftKey] = text } }
    }
    private func send() {
        sending = true
        error = nil
        Task {
            do {
                try await graph.xInteractions.write(
                    owner, post: post, action: quote ? .quote : .reply, text: text)
                if let draftKey { graph.xInteractions.drafts.removeValue(forKey: draftKey) }
                sending = false
                dismiss()
                onSent?()
                graph.toasts.show("发送成功")
            } catch {
                sending = false
                self.error = loadErrorMessage(error)
            }
        }
    }
}
