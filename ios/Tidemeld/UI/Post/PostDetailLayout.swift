import SwiftUI

/// One detail layout for every platform: post, response header, paged rows and action toolbar.
struct PostDetailLayout<Post: View, Header: View, Responses: View>: View {
    var actions: PostInteractionActions?
    let refresh: () async throws -> Void
    @ViewBuilder let post: () -> Post
    @ViewBuilder let responseHeader: () -> Header
    @ViewBuilder let responses: () -> Responses
    @Environment(AppGraph.self) private var graph
    @State private var actionsVisible = true
    var body: some View {
        List {
            post()
            Section {
                responses()
            } header: {
                responseHeader().readingWidth().listHeader()
            }
        }.listStyle(.plain).listSectionSpacing(0).appListStyle().loadsMoreAsScrolled()
            .refreshable {
                do { try await refresh() } catch {
                    graph.toasts.showError(error, router: graph.router)
                }
            }
            .toolbar { if let actions { PostDetailToolbar(actions: actions) } }
            .bottomBarHidesOnScroll($actionsVisible)
    }
}
