import Observation
import SwiftUI

/// The posts found for a query, newest first, with the topic searched for, if
/// one was.
@MainActor @Observable
final class SearchResultsModel {
    let query: String
    /// The topic searched for, as the first page describes it; nil when the
    /// query is no topic.
    private(set) var topic: Topic?
    private(set) var results: PagedList<Status>?

    init(query: String) { self.query = query }

    func start(_ api: WeiboAPI) {
        guard results == nil else { return }
        let query = query
        let list = PagedList<Status>(
            fetch: { [weak self] cursor in
                let results = try await api.searchStatuses(query, page: cursor.flatMap(Int.init) ?? 1)
                if cursor == nil { self?.topic = results.topic }
                return results.statuses
            },
            id: \.id)
        results = list
        list.start()
    }
}

/// Weibo's search results for [query], e.g. `#话题#`, on its mobile site:
/// s.weibo.com is laid out for desktops and sends phones there.
func weiboSearchURL(_ query: String) -> URL {
    let topic = query.count > 2 && query.hasPrefix("#") && query.hasSuffix("#")
    // What s.weibo.com redirects phones to: topic or general results.
    return URL.with(
        "https://m.weibo.cn/search", query: [("containerid", topic ? "231522" : "100103"), ("q", query)])
}

/// The posts across Weibo that match a query, newest first, as cards like the
/// timeline's. A topic's lead and counts head its posts.
///
/// Weibo's own results page, ranked and split into tabs (users, videos, …), is
/// a tap away in the in-app browser.
struct SearchResultsPage: View {
    let query: String

    @Environment(AppGraph.self) private var graph
    @State private var model: SearchResultsModel

    init(query: String) {
        self.query = query
        _model = State(wrappedValue: SearchResultsModel(query: query))
    }

    var body: some View {
        Group {
            if let results = model.results {
                List {
                    if let topic = model.topic, results.state.list != nil {
                        TopicHeader(topic: topic).readingWidth().statusRow()
                    }
                    PagedRows(list: results, emptyText: "没有找到相关微博") { status in
                        StatusCard(status: status, actions: actions).readingWidth().statusRow()
                    }
                }
                .listStyle(.plain)
                .appListStyle()
                .tabBarFollowsScroll()
                .refreshable {
                    do {
                        try await results.refresh()
                    } catch {
                        graph.toasts.showError(error, router: graph.router)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
        .navigationTitle(query)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("网页版搜索结果", systemImage: "globe") { graph.router.push(.web(weiboSearchURL(query))) }
            }
        }
        .onAppear { model.start(graph.api) }
    }

    private var actions: StatusCardActions {
        var actions = graph.statusActions
        let base = actions
        let query = query
        // The topic searched for would only open this page again.
        actions.onLink = { link in
            if case .topic(let topic) = link, "#\(topic)#" == query { return }
            base.onLink?(link)
        }
        return actions
    }
}

private struct TopicHeader: View {
    let topic: Topic
    @Environment(\.displayScale) private var scale

    var body: some View {
        let counts = [(topic.reads, "阅读"), (topic.mentions, "讨论"), (topic.authors, "原创人数")]
            .compactMap { count, label in count.flatMap { $0 > 0 ? "\(formatCount($0))\(label)" : nil } }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                if let image = topic.imageURL {
                    WeiboImage(url: image, maxPixels: 56 * scale)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("#\(topic.name)#").font(.headline).lineLimit(2)
                    if !counts.isEmpty {
                        Text(counts.joined(separator: " · ")).font(.caption).foregroundStyle(AppTheme.secondary)
                    }
                }
            }
            if let summary = topic.summary {
                Text("\(Text("导语：").foregroundStyle(AppTheme.secondary))\(summary)").font(.subheadline)
            }
        }
        .foregroundStyle(AppTheme.foreground)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
