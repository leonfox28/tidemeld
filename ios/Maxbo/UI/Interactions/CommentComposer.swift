import PhotosUI
import SwiftUI

/// A comment or reply the user is writing: text, and a picture.
struct CommentDraft: Sendable, Hashable {
    var text = ""
    var picture: DraftPicture? = nil

    /// A picture can go without text, as on weibo.com.
    var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || picture != nil }
}

/// What the user is writing on a page, by what it replies to, kept until sent
/// so closing the sheet loses nothing.
@MainActor
final class CommentDrafts {
    var drafts: [String: CommentDraft] = [:]
}

/// A sheet to write a comment or reply on status [statusId], which [send] posts
/// when the user taps 发送, with the pid of its picture once uploaded.
struct CommentComposerRequest: Identifiable {
    let id = UUID()
    let statusId: String
    let title: String
    let hint: String
    let drafts: CommentDrafts
    let draftKey: String
    let send: (_ text: String, _ pid: String?) async throws -> Void
    /// The message once sent, e.g. 评论成功.
    let sentMessage: String
}

struct CommentComposer: View {
    let request: CommentComposerRequest

    @Environment(AppGraph.self) private var graph
    @Environment(\.dismiss) private var dismiss
    @State private var draft = CommentDraft()
    @State private var sending = false
    @State private var uploading = false
    /// Whether Weibo said comments here may carry a picture, once asked.
    @State private var pictureAllowed: Bool?
    @State private var asking = false
    @State private var picking = false
    @State private var picked: PhotosPickerItem?
    @State private var notice: String?
    @State private var error: WeiboError?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField(request.hint, text: $draft.text, axis: .vertical)
                    .lineLimit(4...10)
                    .focused($focused)
                    .disabled(sending)
                    .onChange(of: draft) { request.drafts.drafts[request.draftKey] = draft }
                if let error { SendError(error: error) }
                if let notice {
                    Text(notice).font(.footnote).foregroundStyle(AppTheme.secondary)
                }
                HStack {
                    if let picture = draft.picture {
                        DraftThumbnail(picture: picture, size: 64, uploading: uploading) {
                            draft.picture = nil
                        }
                        .disabled(sending)
                    } else {
                        Button {
                            pick()
                        } label: {
                            if asking {
                                ProgressView()
                            } else {
                                Label("添加图片", systemImage: "photo.badge.plus")
                            }
                        }
                        .buttonStyle(.glass)
                        .disabled(sending || asking || pictureAllowed == false)
                    }
                    Spacer()
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }.disabled(sending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if sending {
                        ProgressView()
                    } else {
                        Button("发送", systemImage: "paperplane.fill", role: .confirm) { submit() }
                            .disabled(!draft.canSend)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(sending)
        .photosPicker(isPresented: $picking, selection: $picked, matching: .images)
        .onChange(of: picked) { _, item in
            guard let item else { return }
            picked = nil
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { return }
                    draft.picture = DraftPicture(file: try storeDraftPicture(data))
                } catch {
                    notice = "无法读取这张图片"
                }
            }
        }
        .onAppear {
            draft = request.drafts.drafts[request.draftKey] ?? CommentDraft()
            focused = true
        }
    }

    private func pick() {
        notice = nil
        error = nil
        Task {
            // Asked only when the user wants a picture, so opening the sheet
            // requests nothing (PLAN §2).
            if pictureAllowed == nil {
                asking = true
                do {
                    pictureAllowed = try await graph.api.allowsCommentPicture(request.statusId)
                } catch {
                    // As on weibo.com: Weibo still has its say when it is sent.
                    devLog("checkAllowCommentWithPic failed: \(WeiboError.of(error))")
                }
                asking = false
            }
            if pictureAllowed == false {
                notice = "这条微博的评论不能带图"
            } else {
                picking = true
            }
        }
    }

    private func submit() {
        sending = true
        notice = nil
        error = nil
        Task {
            defer {
                sending = false
                uploading = false
            }
            do {
                var picture = draft.picture
                if var unsent = picture, unsent.pid == nil {
                    uploading = true
                    unsent.pid = try await graph.api.uploadPicture(try Data(contentsOf: unsent.file))
                    // Kept, so sending again after a failure doesn't upload it again.
                    picture = unsent
                    draft.picture = unsent
                    uploading = false
                }
                try await request.send(draft.text.trimmingCharacters(in: .whitespacesAndNewlines), picture?.pid)
                request.drafts.drafts[request.draftKey] = nil
                dismiss()
                graph.toasts.show(request.sentMessage)
            } catch {
                self.error = WeiboError.of(error)
            }
        }
    }
}

/// Why sending failed; when Weibo wants a security check first, a way to take
/// it (the sheet closes, the draft stays).
struct SendError: View {
    let error: WeiboError
    @Environment(AppGraph.self) private var graph
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Text(error.message).font(.footnote).foregroundStyle(AppTheme.error)
            if let url = error.captchaURL {
                Button("去验证") {
                    dismiss()
                    graph.router.web = WebRequest(url: url)
                }
                .font(.footnote)
            }
        }
    }
}

/// A picked picture, square, with a way to take it out, dimmed with progress
/// while it uploads.
struct DraftThumbnail: View {
    let picture: DraftPicture
    var size: CGFloat = 96
    var uploading = false
    let onRemove: () -> Void
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .frame(width: size, height: size)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                if uploading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .task(id: picture.file) {
                let file = picture.file
                let pixels = size * 3
                image = await Task.detached {
                    (try? Data(contentsOf: file)).flatMap { ImageLoader.decode($0, maxPixels: pixels) }
                }.value
            }
            .overlay(alignment: .topTrailing) {
                if !uploading {
                    Button("移除图片", systemImage: "xmark", action: onRemove)
                        .labelStyle(.iconOnly)
                        .font(.caption2.weight(.bold))
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.mini)
                        .padding(4)
                }
            }
    }
}
