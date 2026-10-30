import Foundation

#if DEBUG
/// Opens a page named by the `-maxbo-open` launch argument, in debug builds
/// only, so a page can be checked without tapping through to it:
/// `login`, `compose`, `settings`, `about`, `tab/<home|search|notifications|me>`,
/// `status/<id>`, `u/<uid>`, `n/<screen name>`, `results/<query>`, and from
/// the home timeline once loaded, `first/<status|pic|video|user|thread>`.
@MainActor
enum DebugLaunch {
    /// The diagnostics check to run as the page opens, once.
    static var autorun: String?

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
        case "first": Task { await openFirst(rest, graph) }
        case "diag":
            // Runs a check of the diagnostics page: `reads` or `renewal`.
            autorun = rest
            router.tab = .me
            router.push(.diagnostics)
        default: devLog("debug launch: unknown \(path)")
        }
    }

    /// Opens what the first post of the home timeline that has [kind] leads to.
    private static func openFirst(_ kind: String, _ graph: AppGraph) async {
        let timeline = graph.timeline
        timeline.start()
        while timeline.state.list == nil {
            if case .failed = timeline.state { return }
            try? await Task.sleep(for: .milliseconds(200))
        }
        let statuses = timeline.items.flatMap { [$0] + ($0.retweeted.map { [$0] } ?? []) }
        let actions = graph.statusActions
        switch kind {
        case "status": statuses.first.map { actions.onOpen?($0) }
        case "user": statuses.first?.user.map { actions.onUser?($0) }
        case "pic":
            if let status = statuses.first(where: { !$0.pics.isEmpty }) {
                actions.onPicture?(status.pics, 0, status, nil)
            }
        case "live":
            if let status = statuses.first(where: { $0.pics.contains { $0.liveVideo != nil } }) {
                let index = status.pics.firstIndex { $0.liveVideo != nil }!
                actions.onPicture?(status.pics, index, status, nil)
            }
        case "video":
            if let status = statuses.first(where: { $0.video != nil }) { actions.onVideo?(status, nil) }
        case "thread":
            // The first post with comments, its first comment with replies.
            for status in statuses.prefix(10) where status.commentsCount > 0 {
                guard let author = status.user?.id,
                    let page = try? await graph.api.fetchComments(statusId: status.id, authorId: author, order: .hot),
                    let comment = page.items.first(where: { $0.replyCount > 0 })
                else { continue }
                graph.router.push(.comments(CommentThread(root: comment, statusId: status.id, statusAuthorId: author)))
                return
            }
        default: break
        }
    }
}
#endif
