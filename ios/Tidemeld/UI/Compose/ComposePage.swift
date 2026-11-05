import PhotosUI
import SwiftUI

/// Writing a new post: text, up to nine pictures, and who can see it. The draft
/// outlives the sheet; pictures go up only when the user sends it.
struct ComposePage: View {
    @Environment(AppGraph.self) private var graph
    @Environment(\.dismiss) private var dismiss
    @State private var picked: [PhotosPickerItem] = []
    /// Whether pictures just picked are still being read in, which sending
    /// waits for: they aren't in the draft yet.
    @State private var reading = false
    /// The security check Weibo asked for, over the sheet, which stays: the
    /// user sends again from it once through.
    @State private var web: WebRequest?
    @State private var sending = false
    /// Which picture (from 0) is going up, while one is.
    @State private var uploading: Int?
    @State private var error: WeiboError?
    @State private var notice: String?

    var body: some View {
        @Bindable var drafts = graph.composeDraft
        let draft = drafts.draft
        PostEditor(
            title: "发微博", hint: "分享新鲜事…", text: $drafts.draft.text,
            sending: sending, canSend: draft.canSend && !reading,
            failure: error.map(AppFailure.of), notice: notice,
            progress: reading ? "正在读取图片…" : uploading.map { "正在上传图片 \($0 + 1)/\(draft.pictures.count)" },
            onSend: send,
            onRecover: { recovery in
                if case .verify(let url) = recovery {
                    web = WebRequest(url: url)
                } else {
                    dismiss()
                    graph.router.recover(recovery)
                }
            }, attachments: { pictures(draft) },
            options: {
                HStack {
                    PhotosPicker(
                        selection: $picked, maxSelectionCount: max(1, maxDraftPictures - draft.pictures.count),
                        matching: .images
                    ) {
                        Label("添加图片", systemImage: "photo.on.rectangle.angled")
                    }.disabled(reading || draft.pictures.count >= maxDraftPictures)
                    Spacer()
                    Picker("可见范围", selection: $drafts.draft.visibility) {
                        ForEach(StatusVisibility.choices, id: \.self) {
                            Label($0.label, systemImage: $0.symbol).tag($0)
                        }
                    }.pickerStyle(.menu)
                }
            }
        )
        .sheet(item: $web) { WebSheet(request: $0) }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            reading = true
            Task {
                await add(items)
                reading = false
            }
        }
    }

    @ViewBuilder
    private func pictures(_ draft: ComposeDraft) -> some View {
        if !draft.pictures.isEmpty {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Array(draft.pictures.enumerated()), id: \.element.id) { i, picture in
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            GeometryReader { geo in
                                DraftThumbnail(picture: picture, size: geo.size.width, uploading: uploading == i) {
                                    graph.composeDraft.removePicture(picture.id)
                                }
                            }
                        }
                        .disabled(sending)
                }
            }
        }
    }

    private func add(_ items: [PhotosPickerItem]) async {
        var files: [URL] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
                let file = try? storeDraftPicture(data)
            {
                files.append(file)
            }
        }
        let left = graph.composeDraft.addPictures(files)
        notice =
            left > 0 ? "最多只能添加 \(maxDraftPictures) 张图片" : files.count < items.count ? "有图片无法读取" : nil
    }

    private func send() {
        sending = true
        error = nil
        notice = nil
        Task {
            defer {
                sending = false
                uploading = nil
            }
            do {
                try await graph.composeDraft.send { uploading = $0 }
                dismiss()
                graph.toasts.show("发送成功")
            } catch {
                self.error = WeiboError.of(error)
            }
        }
    }
}

/// Reposting a status, with a reason, who can see it, and whether it also goes
/// as a comment. The text stays as a draft until sent.
struct RepostSheet: View {
    let request: RepostRequest

    @Environment(AppGraph.self) private var graph
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    /// Before the chain of the repost reposted, so what the user writes goes
    /// ahead of it, as Weibo has it.
    @State private var selection: TextSelection?
    @State private var visibility: StatusVisibility = .public
    @State private var alsoComment = false
    @State private var sending = false
    @State private var error: WeiboError?

    var body: some View {
        let status = request.status
        PostEditor(
            title: "转发", hint: "说说分享心得…", text: $text, selection: $selection,
            sending: sending, sendLabel: "转发", failure: error.map(AppFailure.of), onSend: send,
            onRecover: { recovery in
                dismiss()
                graph.router.recover(recovery)
            }, attachments: {},
            options: {
                Picker("可见范围", selection: $visibility) {
                    ForEach(StatusVisibility.choices, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("同时评论", isOn: $alsoComment)
            }
        )
        .onChange(of: text) { graph.repostDrafts[status.id] = text }
        .presentationDetents([.medium, .large])
        .onAppear {
            text = graph.repostDrafts[status.id] ?? request.quote
            selection = TextSelection(insertionPoint: text.startIndex)
        }
    }

    private func send() {
        sending = true
        error = nil
        Task {
            defer { sending = false }
            do {
                let repost = try await graph.api.repostStatus(
                    request.status.id, text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    alsoComment: alsoComment, visibility: visibility)
                graph.repostDrafts[request.status.id] = nil
                dismiss()
                graph.reposted(request, repost: repost)
            } catch {
                self.error = WeiboError.of(error)
            }
        }
    }
}
