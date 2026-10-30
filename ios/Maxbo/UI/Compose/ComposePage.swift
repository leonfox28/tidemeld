import PhotosUI
import SwiftUI

/// Writing a new post: text, up to nine pictures, and who can see it. The draft
/// outlives the sheet; pictures go up only when the user sends it.
struct ComposePage: View {
    @Environment(AppGraph.self) private var graph
    @Environment(\.dismiss) private var dismiss
    @State private var picked: [PhotosPickerItem] = []
    @State private var sending = false
    /// Which picture (from 0) is going up, while one is.
    @State private var uploading: Int?
    @State private var error: WeiboError?
    @State private var notice: String?
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var drafts = graph.composeDraft
        let draft = drafts.draft
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("分享新鲜事…", text: $drafts.draft.text, axis: .vertical)
                        .lineLimit(5...)
                        .focused($focused)
                        .disabled(sending)
                    if let error { SendError(error: error) }
                    if let notice {
                        Text(notice).font(.footnote).foregroundStyle(AppTheme.secondary)
                    }
                    pictures(draft)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .appBackground()
            .navigationTitle("发微博")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }.disabled(sending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if sending {
                        ProgressView()
                    } else {
                        Button("发送", systemImage: "paperplane.fill", role: .confirm) { send() }
                            .disabled(!draft.canSend)
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    PhotosPicker(
                        selection: $picked, maxSelectionCount: max(1, maxDraftPictures - draft.pictures.count),
                        matching: .images
                    ) {
                        Label("添加图片", systemImage: "photo.on.rectangle.angled")
                    }
                    .disabled(sending || draft.pictures.count >= maxDraftPictures)
                    Spacer()
                    Menu {
                        Picker("可见范围", selection: $drafts.draft.visibility) {
                            ForEach(StatusVisibility.choices, id: \.self) { visibility in
                                Label(visibility.label, systemImage: visibility.symbol).tag(visibility)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: draft.visibility.symbol)
                            Text(draft.visibility.label)
                        }
                        .padding(.horizontal, 6)
                    }
                    .disabled(sending)
                }
            }
        }
        .interactiveDismissDisabled(sending)
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task { await add(items) }
        }
        .onAppear { focused = true }
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
            if let data = try? await item.loadTransferable(type: Data.self), let file = try? storeDraftPicture(data) {
                files.append(file)
            }
        }
        let left = graph.composeDraft.addPictures(files)
        notice = left > 0 ? "最多只能添加 \(maxDraftPictures) 张图片" : files.count < items.count ? "有图片无法读取" : nil
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
    @State private var visibility: StatusVisibility = .public
    @State private var alsoComment = false
    @State private var sending = false
    @State private var error: WeiboError?
    @FocusState private var focused: Bool

    var body: some View {
        let status = request.status
        NavigationStack {
            Form {
                Section {
                    // Weibo puts in 转发微博 when there is nothing.
                    TextField("说说分享心得…", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focused)
                        .disabled(sending)
                        .onChange(of: text) { graph.repostDrafts[status.id] = text }
                    if let error { SendError(error: error) }
                }
                .listRowBackground(AppTheme.surface)
                Section {
                    Picker("可见范围", selection: $visibility) {
                        ForEach(StatusVisibility.choices, id: \.self) { Text($0.label).tag($0) }
                    }
                    Toggle("同时评论", isOn: $alsoComment)
                }
                .disabled(sending)
                .listRowBackground(AppTheme.surface)
            }
            .appListStyle()
            .navigationTitle("转发")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }.disabled(sending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if sending {
                        ProgressView()
                    } else {
                        Button("转发", systemImage: "arrow.2.squarepath", role: .confirm) { send() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(sending)
        .onAppear {
            text = graph.repostDrafts[status.id] ?? request.quote
            focused = true
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
