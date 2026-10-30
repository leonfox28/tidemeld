import SwiftUI

@main
struct MaxboApp: App {
    @State private var graph = AppGraph.create()

    var body: some Scene {
        WindowGroup {
            RootView().environment(graph)
        }
    }
}
