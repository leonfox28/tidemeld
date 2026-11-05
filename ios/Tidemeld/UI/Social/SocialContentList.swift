import SwiftUI

struct SocialContentList<Content: View>: View {
    let refresh: () async throws -> Void
    @ViewBuilder let content: () -> Content
    @Environment(AppGraph.self) private var graph
    var body: some View {
        List { content() }.listStyle(.plain).appListStyle().loadsMoreAsScrolled()
            .refreshable {
                do { try await refresh() } catch { graph.toasts.showError(error, router: graph.router) }
            }
    }
}
