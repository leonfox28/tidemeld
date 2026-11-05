import SwiftUI

struct SocialSearchField: View {
    @Binding var query: String
    let hint: String
    var focused: FocusState<Bool>.Binding
    let onSearch: (String) -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.secondary)
            TextField(hint, text: $query)
                .focused(focused)
                .submitLabel(.search)
                .onSubmit {
                    let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { return }
                    focused.wrappedValue = false
                    onSearch(value)
                }

            if !query.isEmpty {
                Button("清除", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(AppTheme.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(AppTheme.elevated, in: Capsule())
        .readingWidth()
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}
