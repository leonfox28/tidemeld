import Foundation
import Observation
import SwiftUI

/// The tabs at the root of the app.
enum AppTab: Hashable, CaseIterable {
    case home, search, notifications, me
}

/// A page pushed onto a tab's stack. Like the Android app's routes, a route may
/// carry what the previous page already has, such as the status that was
/// tapped; routes compare by what they show, not by that.
enum Route: Hashable {
    /// A status and its comments; [initial] shows until the full status loads.
    case status(id: String, initial: Status?)
    /// A comment and its replies ("楼中楼").
    case comments(CommentThread)
    case profile(uid: String, initial: WeiboUser?)
    /// A profile by screen name, as @mentions name users.
    case profileByName(String)
    case searchResults(String)
    /// A web page in the in-app browser.
    case web(URL)
    case settings
    case textSize
    case about
    case licenses
    /// Debug builds only.
    case diagnostics

    private var key: String {
        switch self {
        case .status(let id, _): "status:\(id)"
        case .comments(let thread): "comments:\(thread.root.id)"
        case .profile(let uid, _): "profile:\(uid)"
        case .profileByName(let name): "name:\(name)"
        case .searchResults(let query): "search:\(query)"
        case .web(let url): "web:\(url.absoluteString)"
        case .settings: "settings"
        case .textSize: "textSize"
        case .about: "about"
        case .licenses: "licenses"
        case .diagnostics: "diagnostics"
        }
    }

    static func == (a: Route, b: Route) -> Bool { a.key == b.key }
    func hash(into hasher: inout Hasher) { hasher.combine(key) }
}

/// A comment's thread, as its page needs it: the comment, and the status it is
/// on (for its author, whom the replies endpoint wants).
struct CommentThread: Sendable, Hashable {
    let root: Comment
    let statusId: String
    let statusAuthorId: String
}

/// Pictures to view, opened at [index]; those of status [statusId], if any,
/// where the viewer gets a live photo's video afresh once its URL has expired.
struct ViewerRequest: Identifiable {
    let id = UUID()
    let pics: [PicInfo]
    let index: Int
    var statusId: String? = nil
    /// The id of the tile it zooms out of, in the media namespace.
    var sourceID: String? = nil
}

/// The video of status [statusId], or its [index]th in a post mixing pictures
/// and videos.
struct VideoRequest: Identifiable {
    let id = UUID()
    let statusId: String
    var index: Int? = nil
    var initial: Status? = nil
}

/// A web page shown over the app, calling [onClose] once the user leaves it, as
/// for a security check after which a load is tried again.
struct WebRequest: Identifiable {
    let id = UUID()
    let url: URL
    var onClose: (() -> Void)? = nil
}

/// Where the user is: the selected tab, each tab's stack of pages, and what is
/// presented over them.
@MainActor @Observable
final class Router {
    var tab: AppTab = .home
    var paths: [AppTab: [Route]] = [:]

    var showingLogin = false
    var showingCompose = false
    var viewer: ViewerRequest?
    var video: VideoRequest?
    var web: WebRequest?
    var repost: RepostRequest?
    var deletion: DeleteRequest?
    var commentComposer: CommentComposerRequest?

    /// While set, the tab bar stays expanded; see [expandTabBar].
    private(set) var tabBarPinned = false
    @ObservationIgnored private var unpin: Task<Void, Never>?

    /// Bumped each time the selected tab is tapped again.
    private(set) var reselects: [AppTab: Int] = [:]

    func path(_ tab: AppTab) -> Binding<[Route]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }

    /// The tab selection, noting a tap on the tab that is already selected.
    var selection: Binding<AppTab> {
        Binding(
            get: { self.tab },
            set: { tab in
                if tab == self.tab, (self.paths[tab] ?? []).isEmpty {
                    self.reselects[tab, default: 0] += 1
                }
                self.tab = tab
            })
    }

    /// Brings the minimized tab bar back, as the content scrolls back. The
    /// system minimizes it as the content scrolls on, but only expands it again
    /// at the top or the end: briefly not letting it minimize does.
    func expandTabBar() {
        tabBarPinned = true
        unpin?.cancel()
        unpin = Task {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { tabBarPinned = false }
        }
    }

    func push(_ route: Route) {
        paths[tab, default: []].append(route)
    }

    func pop() {
        _ = paths[tab]?.popLast()
    }

    /// Opens the results of searching for [query]; `#话题#` searches the topic.
    func openSearch(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty { push(.searchResults(query)) }
    }
}
