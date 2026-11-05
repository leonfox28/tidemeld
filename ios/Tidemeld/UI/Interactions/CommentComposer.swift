import PhotosUI
import SwiftUI

/// A comment or reply the user is writing: text, and a picture.
struct CommentDraft: Sendable, Hashable {
    var text = ""
    var picture: DraftPicture? = nil

    /// A picture can go without text, as on weibo.com.
    var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || picture != nil
    }
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
    var body: some View {
        PostComposer(
            request: PostComposerRequest(
                title: request.title, hint: request.hint, drafts: request.drafts,
                draftKey: request.draftKey,
                send: request.send, sentMessage: request.sentMessage,
                attachments: PostAttachments(
                    allowed: { try await graph.api.allowsCommentPicture(request.statusId) },
                    upload: { try await graph.api.uploadPicture(try readDraftPicture($0)) },
                    unavailableMessage: "这条微博的评论不能带图")))
    }
}

/// Presentation adapter for existing editor callers and verification navigation.
struct SendError: View {
    let error: Error
    var onVerify: ((URL) -> Void)? = nil
    @Environment(AppGraph.self) private var graph
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        FailureNotice(failure: AppFailure.of(error)) { recovery in
            if case .verify(let url) = recovery, let onVerify {
                onVerify(url)
            } else {
                dismiss()
                graph.router.recover(recovery)
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
                    (try? Data(contentsOf: file)).flatMap {
                        ImageLoader.decode($0, maxPixels: pixels)
                    }
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
