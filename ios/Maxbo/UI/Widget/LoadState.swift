import SwiftUI

/// A failure in place of content, with a retry button; when Weibo wants a
/// security check first, a button to take it.
struct ErrorRetry: View {
    let error: WeiboError
    let onRetry: () -> Void
    @Environment(AppGraph.self) private var graph

    var body: some View {
        ContentUnavailableView {
            Label(error.message, systemImage: error == .network ? "wifi.slash" : "exclamationmark.triangle")
        } actions: {
            if let url = error.captchaURL {
                Button("去验证") { graph.router.web = WebRequest(url: url, onClose: onRetry) }
                    .buttonStyle(.glassProminent)
            } else {
                Button("重试", action: onRetry).buttonStyle(.glass)
            }
        }
    }
}

/// The end of a paged list: a spinner while the next page loads, the error and
/// a retry button when it failed, or a note that nothing is left.
struct LoadMoreFooter<T>: View {
    let list: PagedState<T>
    let onLoadMore: () -> Void
    var endText = "没有更多了"
    @Environment(AppGraph.self) private var graph

    var body: some View {
        Group {
            if list.loadingMore {
                ProgressView()
            } else if let error = list.loadMoreError {
                VStack(spacing: 6) {
                    Text(error.message).font(.footnote).foregroundStyle(AppTheme.secondary)
                    if let url = error.captchaURL {
                        Button("去验证") { graph.router.web = WebRequest(url: url, onClose: onLoadMore) }
                    } else {
                        Button("重试", action: onLoadMore)
                    }
                }
            } else if list.hasMore {
                // Normally replaced by the spinner before it scrolls into view;
                // kept for lists too short to scroll.
                Button("加载更多", action: onLoadMore)
            } else {
                Text(endText).font(.footnote).foregroundStyle(AppTheme.secondary)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        // Loads the next page as the footer comes near: only scrolling brings
        // it, so a list too short to scroll waits for its button. After a
        // failure, loading more waits for the retry button.
        .onAppear {
            if list.hasMore, list.loadMoreError == nil { onLoadMore() }
        }
    }
}

/// A paged list's rows: its items, or a spinner or the error while the first
/// page loads, an empty note, and a footer.
struct PagedRows<T: Sendable, Row: View>: View {
    let list: PagedList<T>
    var emptyText = "暂无内容"
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
            if state.items.isEmpty, !state.hasMore {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(state.items.map { (list.idOf($0), $0) }, id: \.0) { item in
                    row(item.1)
                }
                LoadMoreFooter(list: state) { Task { await list.loadMore() } }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
    }
}
