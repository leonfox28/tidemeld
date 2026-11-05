import PhotosUI
import SwiftUI

struct PostAttachments {
    let allowed: () async throws -> Bool
    let upload: (DraftPicture) async throws -> String
    let unavailableMessage: String
}

struct PostComposerRequest {
    let title: String
    let hint: String
    let drafts: CommentDrafts
    let draftKey: String
    let send: (String, String?) async throws -> Void
    let sentMessage: String
    var context: String? = nil
    var attachments: PostAttachments? = nil
}

struct PostComposer: View {
    let request: PostComposerRequest

    @Environment(AppGraph.self) private var graph
    @Environment(\.dismiss) private var dismiss
    @State private var draft = CommentDraft()
    @State private var sending = false
    @State private var uploading = false
    /// Whether the platform permits attachments here, once asked.
    @State private var pictureAllowed: Bool?
    @State private var asking = false
    @State private var picking = false
    @State private var picked: PhotosPickerItem?
    /// Whether the picture just picked is still being read in, which sending
    /// waits for: it isn't in the draft yet.
    @State private var reading = false
    @State private var notice: String?
    @State private var error: WeiboError?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if let context = request.context {
                    Text(context).font(.subheadline).foregroundStyle(AppTheme.accent)
                }
                TextField(request.hint, text: $draft.text, axis: .vertical)
                    .lineLimit(4...10)
                    .focused($focused)
                    .disabled(sending)
                    .onChange(of: draft) { request.drafts.drafts[request.draftKey] = draft }
                if let error { SendError(error: error) }
                if let notice {
                    Text(notice).font(.footnote).foregroundStyle(AppTheme.secondary)
                }
                if request.attachments != nil {
                    HStack {
                        if let picture = draft.picture {
                            DraftThumbnail(picture: picture, size: 64, uploading: uploading) {
                                discardDraftPictures([picture])
                                draft.picture = nil
                            }
                            .disabled(sending)
                        } else if reading {
                            ProgressView().frame(width: 64, height: 64)
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
                            .disabled(!draft.canSend || reading)
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
            reading = true
            Task {
                defer { reading = false }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        return
                    }
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
        guard let support = request.attachments else { return }
        notice = nil
        error = nil
        Task {
            // Asked only when the user wants a picture, so opening the sheet
            // requests nothing (PLAN §2).
            if pictureAllowed == nil {
                asking = true
                do {
                    pictureAllowed = try await support.allowed()
                } catch {
                    // The platform validates attachment support again when sending.
                    devLog("Attachment capability check failed: \(WeiboError.of(error))")
                }
                asking = false
            }
            if pictureAllowed == false {
                notice = support.unavailableMessage
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
                    guard let support = request.attachments else {
                        throw WeiboError.api("此操作不支持图片")
                    }
                    unsent.pid = try await support.upload(unsent)
                    // Kept, so sending again after a failure doesn't upload it again.
                    picture = unsent
                    draft.picture = unsent
                    uploading = false
                }
                try await request.send(
                    draft.text.trimmingCharacters(in: .whitespacesAndNewlines), picture?.pid)
                request.drafts.drafts[request.draftKey] = nil
                if let picture { discardDraftPictures([picture]) }
                dismiss()
                graph.toasts.show(request.sentMessage)
            } catch {
                self.error = WeiboError.of(error)
            }
        }
    }
}
