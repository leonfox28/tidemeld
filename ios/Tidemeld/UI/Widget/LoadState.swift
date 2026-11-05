import SwiftUI

/// A failure in place of content, with a retry button; when Weibo wants a
/// security check first, a button to take it.
struct ErrorRetry: View {
    let error: Error
    let onRetry: () -> Void
    @Environment(AppGraph.self) private var graph

    var body: some View {
        let failure = AppFailure.of(error)
        ContentUnavailableView {
            Label(
                failure.message, systemImage: failure.isNetwork ? "wifi.slash" : "exclamationmark.triangle")
        } actions: {
            if let recovery = failure.recovery {
                Button(recovery.label) { graph.router.recover(recovery, onVerified: onRetry) }
                    .buttonStyle(.glassProminent)
            } else {
                Button("重试", action: onRetry).buttonStyle(.glass)
            }
        }
    }
}

/// The end of a paged list: a spinner while the next page loads, the error and
/// a retry button when it failed, or a note that nothing is left.
///
/// The next page loads as the user scrolls on to the footer (in a list with
/// `loadsMoreAsScrolled()`), or scrolls on with it in view; nothing else loads
/// it, so a list too short to scroll waits for its button, as in the Kotlin app
/// (PLAN §2). After a failure, loading more waits for the retry button.
struct LoadMoreFooter<T>: View {
    let list: PagedState<T>
    let onLoadMore: () -> Void
    var endText = "没有更多了"
    @Environment(AppGraph.self) private var graph
    @Environment(\.scrollingTowardEnd) private var scrolling
    @State private var onScreen = false

    var body: some View {
        Group {
            if list.loadingMore {
                ProgressView()
            } else if let error = list.loadMoreError {
                VStack(spacing: 6) {
                    Text(error.message).font(.footnote).foregroundStyle(AppTheme.secondary)
                    if let recovery = error.recovery {
                        Button(recovery.label) { graph.router.recover(recovery, onVerified: onLoadMore) }
                    } else {
                        Button("重试", action: onLoadMore)
                    }
                }
            } else if list.hasMore {
                // Normally replaced by the spinner before it scrolls into view;
                // for lists too short to scroll.
                Button("加载更多", action: onLoadMore)
            } else {
                Text(endText).font(.footnote).foregroundStyle(AppTheme.secondary)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .onAppear {
            onScreen = true
            loadIfScrolled()
        }
        .onDisappear { onScreen = false }
        .onChange(of: scrolling) { if onScreen { loadIfScrolled() } }
    }

    private func loadIfScrolled() {
        if scrolling, list.hasMore, !list.loadingMore, list.loadMoreError == nil { onLoadMore() }
    }
}

extension EnvironmentValues {
    /// Whether the user is scrolling the list on toward its end; see
    /// `loadsMoreAsScrolled()`.
    @Entry var scrollingTowardEnd = false
}

extension View {
    /// Lets the footer of this list load the next page as the user scrolls to
    /// it (see [LoadMoreFooter]); without it, only its button does.
    func loadsMoreAsScrolled(enabled: Bool = true) -> some View { modifier(LoadsMoreAsScrolled(enabled: enabled)) }
}

private struct LoadsMoreAsScrolled: ViewModifier {
    var enabled = true
    @State private var forward = false
    @State private var settling: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            // From the offset alone: the scroll phase doesn't change on a
            // `List` as it is dragged.
            .onScrollGeometryChange(for: CGFloat.self) {
                $0.contentOffset.y + $0.contentInsets.top
            } action: {
                old, new in
                guard enabled else {
                    forward = false
                    settling?.cancel()
                    return
                }
                // On toward the end, from below the top: springing back from a
                // pull to refresh doesn't count.
                let forward = new > old && new > 0
                if forward != self.forward { self.forward = forward }
                // Until the list has come to rest.
                settling?.cancel()
                settling =
                    forward
                    ? Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        if !Task.isCancelled { self.forward = false }
                    } : nil
            }
            .environment(\.scrollingTowardEnd, forward)
    }
}

/// A paged list's rows: its items, or a spinner or the error while the first
/// page loads, an empty note, and a footer.
struct PagedRows<T: Sendable, Row: View>: View {
    let list: PagedList<T>
    var emptyText = "暂无内容"
    /// Nested responses can be previewed in their parent's row without changing pagination.
    var include: (T) -> Bool = { _ in true }
    @ViewBuilder let row: (T) -> Row

    var body: some View {
        switch list.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(32)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        case .failed(let error):
            ErrorRetry(error: error) { list.reload() }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        case .ready(let state):
            let items = state.items.filter(include)
            if items.isEmpty, !state.hasMore {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(items.map { (list.idOf($0), $0) }, id: \.0) { item in
                    row(item.1)
                }
                LoadMoreFooter(list: state) { Task { await list.loadMore() } }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
    }
}
