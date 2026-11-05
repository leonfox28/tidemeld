import SwiftUI

@main
struct TidemeldApp: App {
    @State private var graph = AppGraph.create()

    var body: some Scene {
        WindowGroup {
            RootView().environment(graph)
        }
    }
}
