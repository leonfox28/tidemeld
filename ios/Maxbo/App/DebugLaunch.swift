import Foundation

#if DEBUG
/// Opens a page named by the `-maxbo-open` launch argument, in debug builds
/// only, so a page can be checked without tapping through to it:
/// `login`, `compose`, `settings`, `about`, `tab/<home|search|notifications|me>`,
/// `status/<id>`, `u/<uid>`, `n/<screen name>`, `results/<query>`.
@MainActor
enum DebugLaunch {
    static func apply(_ graph: AppGraph) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-maxbo-open"), index + 1 < arguments.count else { return }
        open(arguments[index + 1], graph)
    }

    static func open(_ path: String, _ graph: AppGraph) {
        let router = graph.router
        let parts = path.split(separator: "/", maxSplits: 1).map(String.init)
        let rest = parts.count > 1 ? (parts[1].removingPercentEncoding ?? parts[1]) : ""
        switch parts.first {
        case "login": router.showingLogin = true
        case "compose": router.showingCompose = true
        case "settings": router.tab = .me; router.push(.settings)
        case "about": router.tab = .me; router.push(.about)
        case "tab":
            router.tab = ["search": .search, "notifications": .notifications, "me": .me][rest] ?? .home
        case "status": router.push(.status(id: rest, initial: nil))
        case "u": router.push(.profile(uid: rest, initial: nil))
        case "n": router.push(.profileByName(rest))
        case "results": router.push(.searchResults(rest))
        default: devLog("debug launch: unknown \(path)")
        }
    }
}
#endif
