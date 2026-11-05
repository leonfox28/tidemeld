import SwiftUI

/// The editor surface for new posts, comments and reposts. Platform adapters
/// own drafts, attachment capabilities, submission and recovery navigation.
struct PostEditor<Attachments: View, Options: View>: View {
    let title: String
    let hint: String
    @Binding var text: String
    var selection: Binding<TextSelection?>? = nil
    var sending = false
    var canSend = true
    var sendLabel = "发送"
    var context: String? = nil
    var failure: AppFailure? = nil
    var notice: String? = nil
    var progress: String? = nil
    let onSend: () -> Void
    var onRecover: ((FailureRecovery) -> Void)? = nil
    @ViewBuilder let attachments: () -> Attachments
    @ViewBuilder let options: () -> Options
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var localSelection: TextSelection?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let context { Text(context).font(.subheadline).foregroundStyle(AppTheme.accent) }
                    TextField(hint, text: $text, selection: selection ?? $localSelection, axis: .vertical)
                        .lineLimit(4...).focused($focused).disabled(sending)
                    if let failure, !failure.isCancelled {
                        FailureNotice(failure: failure, onRecover: onRecover)
                    }
                    if let notice { Text(notice).font(.footnote).foregroundStyle(AppTheme.secondary) }
                    if let progress {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(progress).font(.footnote)
                        }
                    }
                    attachments().disabled(sending)
                    options().disabled(sending)
                }.padding(16)
            }
            .scrollDismissesKeyboard(.interactively).appBackground()
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }.disabled(sending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if sending {
                        ProgressView()
                    } else {
                        Button(sendLabel, systemImage: "paperplane.fill", role: .confirm, action: onSend)
                            .disabled(!canSend)
                    }
                }
            }
        }
        .interactiveDismissDisabled(sending)
        .onAppear { focused = true }
    }
}
