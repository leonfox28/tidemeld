import Observation
import SwiftUI

/// The hot search list: loaded when the tab is first opened, and again only on
/// pull to refresh.
@MainActor @Observable
final class HotSearchModel {
    private(set) var hot: HotSearch?
    private(set) var error: WeiboError?
    @ObservationIgnored private var api: WeiboAPI?

    func start(_ api: WeiboAPI) {
        guard self.api == nil else { return }
        self.api = api
        reload()
    }

    func reload() {
        hot = nil
        error = nil
        Task {
            do {
                hot = try await api!.fetchHotSearch()
            } catch {
                self.error = WeiboError.of(error)
            }
        }
    }

    /// Throws on failure, the list staying as it was.
    func refresh() async throws {
        hot = try await api!.fetchHotSearch()
    }
}

/// The search tab: a search field over the hot search list. A search, as a hot
/// search entry, opens the posts found for it.
struct SearchPage: View {
    @Environment(AppGraph.self) private var graph
    @State private var model = HotSearchModel()
    @State private var query = ""
    @State private var atTop = true

    var body: some View {
        Group {
            switch graph.session.state {
            case .signedOut(let expired): LoginPrompt(expired: expired)
            case .signedIn: hotList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
        .navigationTitle("搜索")
        .searchable(text: $query, prompt: "搜索微博")
        .onSubmit(of: .search) {
            graph.router.openSearch(query)
        }
    }

    @ViewBuilder
    private var hotList: some View {
        if let hot = model.hot {
            ScrollViewReader { proxy in
                List {
                    Section {
                        ForEach(hot.pinned) { HotSearchRow(item: $0, pinned: true) }
                        ForEach(hot.items) { HotSearchRow(item: $0) }
                    } header: {
                        Text("微博热搜").id("top")
                    }
                    .listRowBackground(AppTheme.surface)
                }
                .appListStyle()
                .refreshable {
                    do {
                        try await model.refresh()
                    } catch {
                        graph.toasts.showError(error, router: graph.router)
                    }
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y <= -geometry.contentInsets.top + 4
                } action: { _, top in
                    atTop = top
                }
                // Tapping the open tab again: back to the top, or a refresh
                // from there.
                .onChange(of: graph.router.reselects[.search]) {
                    if atTop {
                        Task { try? await model.refresh() }
                    } else {
                        withAnimation { proxy.scrollTo("top", anchor: .top) }
                    }
                }
            }
        } else if let error = model.error {
            ErrorRetry(error: error) { model.reload() }
        } else {
            ProgressView().task { model.start(graph.api) }
        }
    }
}

// Weibo's colours for the top three.
private let topColors = [Color(rgb: 0xF5222D), Color(rgb: 0xFF6A00), Color(rgb: 0xFAA90E)]

private struct HotSearchRow: View {
    let item: HotSearchItem
    var pinned = false
    @Environment(AppGraph.self) private var graph

    var body: some View {
        Button {
            graph.router.openSearch(item.query)
        } label: {
            HStack(spacing: 8) {
                Group {
                    if pinned {
                        Image(systemName: "pin.fill").foregroundStyle(topColors[0])
                    } else if let rank = item.rank {
                        Text("\(rank)")
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(rank <= 3 ? topColors[rank - 1] : AppTheme.secondary)
                    } else {
                        // Inserted by Weibo outside the ranking.
                        Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(AppTheme.secondary)
                    }
                }
                .frame(width: 28)
                Text(item.word).foregroundStyle(AppTheme.foreground).lineLimit(1)
                if let badge = item.badge {
                    TagLabel(text: badge, color: item.badgeColor.map { Color(rgb: $0) })
                }
                Spacer(minLength: 8)
                if let heat = item.heat, heat > 0 {
                    Text(formatCount(heat)).font(.caption).foregroundStyle(AppTheme.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
