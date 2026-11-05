import SwiftUI

/// One detail layout for every platform: context, post, responses and action toolbar.
struct PostDetailLayout<Context: View, Post: View, Header: View, Responses: View>: View {
    var actions: PostInteractionActions?
    let refresh: () async throws -> Void
    let initialFocus: String?
    @ViewBuilder let context: () -> Context
    @ViewBuilder let post: () -> Post
    @ViewBuilder let responseHeader: () -> Header
    @ViewBuilder let responses: () -> Responses
    @Environment(AppGraph.self) private var graph
    @State private var position: String?
    @State private var actionsVisible = true
    @State private var userScrolling = false

    init(
        actions: PostInteractionActions?, refresh: @escaping () async throws -> Void,
        initialFocus: String? = nil,
        @ViewBuilder context: @escaping () -> Context = { EmptyView() },
        @ViewBuilder post: @escaping () -> Post,
        @ViewBuilder responseHeader: @escaping () -> Header,
        @ViewBuilder responses: @escaping () -> Responses
    ) {
        self.actions = actions
        self.refresh = refresh
        self.initialFocus = initialFocus
        self.context = context
        self.post = post
        self.responseHeader = responseHeader
        self.responses = responses
        _position = State(initialValue: initialFocus)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 0) { context() }.scrollTargetLayout()
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        post().id(initialFocus ?? "post")
                        Section {
                            responses()
                        } header: {
                            responseHeader().readingWidth().background(AppTheme.background)
                        }
                    }
                    .scrollTargetLayout()
                    // A short reply can align at the top without measuring content or offsets.
                    .frame(minHeight: geometry.size.height, alignment: .top)
                }
            }
            .accessibilityElement(children: .contain)
            .scrollPosition(id: $position, anchor: .top)
            .onScrollPhaseChange { _, phase in
                userScrolling = phase == .interacting || phase == .decelerating
            }
            .loadsMoreAsScrolled(enabled: userScrolling)
            .refreshable {
                do { try await refresh() } catch {
                    graph.toasts.showError(error, router: graph.router)
                }
            }
            .bottomBarHidesOnScroll($actionsVisible, enabled: userScrolling)
            .environment(\.detailScrollRows, true)
        }
        .appBackground()
        .toolbar { if let actions { PostDetailToolbar(actions: actions) } }
    }
}

extension EnvironmentValues {
    @Entry var detailScrollRows = false
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

extension View {
    /// A comment or repost as a list row, divided from the next under its text.
    func responseRow() -> some View {
        modifier(ResponseRowStyle())
    }
}

private struct ResponseRowStyle: ViewModifier {
    @Environment(\.detailScrollRows) private var scrollRows
    func body(content: Content) -> some View {
        if scrollRows {
            content.overlay(alignment: .bottom) {
                Rectangle().fill(AppTheme.outline).frame(height: 0.5)
                    .padding(.leading, 58).readingWidth().accessibilityHidden(true)
            }
        } else {
            content.listRowInsets(EdgeInsets())
                .listRowBackground(AppTheme.background)
                .listRowSeparatorTint(AppTheme.outline)
                .alignmentGuide(.listRowSeparatorLeading) { _ in 58 }
        }
    }
}
