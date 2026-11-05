import SwiftUI

/// One detail layout for every platform: post, response header, paged rows and action toolbar.
struct PostDetailLayout<Post: View, Header: View, Responses: View>: View {
    var actions: PostInteractionActions?
    let refresh: () async throws -> Void
    var initialFocus: String? = nil
    @ViewBuilder let post: () -> Post
    @ViewBuilder let responseHeader: () -> Header
    @ViewBuilder let responses: () -> Responses
    @Environment(AppGraph.self) private var graph
    @State private var actionsVisible = true
    @State private var positioned = false
    @State private var trailingSpace: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    var body: some View {
        ScrollViewReader { proxy in
            List {
                post()
                Section {
                    responses()
                } header: {
                    responseHeader().readingWidth().listHeader()
                }
                if initialFocus != nil {
                    Color.clear.frame(height: trailingSpace).plainRow()
                        .environment(\.defaultMinListRowHeight, 0)
                        .anchorPreference(key: DetailBounds.self, value: .bounds) { ["end": $0] }
                        .accessibilityHidden(true)
                }
            }.listStyle(.plain).listSectionSpacing(0).appListStyle()
                .onScrollGeometryChange(for: CGFloat.self) {
                    $0.containerSize.height - $0.contentInsets.top - $0.contentInsets.bottom
                } action: { _, height in
                    viewportHeight = height
                }
                .overlayPreferenceValue(DetailBounds.self) { bounds in
                    GeometryReader { geometry in
                        let remaining = initialFocus.flatMap { bounds[$0] }.flatMap { focal in
                            bounds["end"].map { geometry[$0].minY - geometry[focal].minY }
                        }
                        let space = remaining.map { max(0, viewportHeight - $0) }
                        Color.clear.onChange(of: space, initial: true) { _, space in
                            if let space {
                                // Leave only the room needed to place a short conversation at its focal post.
                                trailingSpace = space
                            }
                        }
                    }.allowsHitTesting(false)
                }
                .loadsMoreAsScrolled(enabled: initialFocus == nil || positioned)
                .refreshable {
                    do { try await refresh() } catch {
                        graph.toasts.showError(error, router: graph.router)
                    }
                }
                .toolbar { if let actions { PostDetailToolbar(actions: actions) } }
                .bottomBarHidesOnScroll($actionsVisible, enabled: initialFocus == nil || positioned)
                .task(id: "\(initialFocus ?? ""):\(trailingSpace)") {
                    guard !positioned, let target = initialFocus else { return }
                    await Task.yield()
                    proxy.scrollTo(target, anchor: .top)
                    // Positioning is not a user scroll and must not fetch more comments.
                    try? await Task.sleep(for: .milliseconds(400))
                    if !Task.isCancelled { positioned = true }
                }
        }
    }
}

private struct DetailBounds: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    /// Marks the current post within the shared conversation layout.
    func detailFocus(_ id: String) -> some View {
        self.id(id).anchorPreference(key: DetailBounds.self, value: .bounds) { [id: $0] }
    }
}

/// Joins contextual posts to the next post without introducing another card layout.
struct PostConversationContext<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
            Rectangle().fill(AppTheme.outline).frame(width: 2, height: 24).padding(.leading, 36)
                .accessibilityHidden(true)
        }
    }
}
