import Foundation
import Observation
import SwiftUI

/// The tabs at the root of the app.
enum AppTab: Hashable, CaseIterable {
    case home, search, notifications, settings
}

/// A page pushed onto a tab's stack. Like the Android app's routes, a route may
/// carry what the previous page already has, such as the status that was
/// tapped; routes compare by what they show, not by that.
enum Route: Hashable {
    case xProfile(owner: String, user: XProfileUser)
    case xStatus(owner: String, id: String, initial: XPost?)
    case accounts
    indirect case account(String, Route)
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
    case accountWeb(String, URL)
    case textSize
    case about
    case privacy
    case terms
    case report(PlatformReport)
    case licenses
    /// Debug builds only.
    case diagnostics

    private var key: String {
        switch self {
        case .xProfile(let owner, let user): "xProfile:\(owner):\(user.id ?? user.handle?.lowercased() ?? "")"
        case .xStatus(let owner, let id, _): "xStatus:\(owner):\(id)"
        case .accounts: "accounts"
        case .account(let owner, let route): "account:\(owner):\(route.key)"
        case .status(let id, _): "status:\(id)"
        case .comments(let thread): "comments:\(thread.root.id)"
        case .profile(let uid, _): "profile:\(uid)"
        case .profileByName(let name): "name:\(name)"
        case .searchResults(let query): "search:\(query)"
        case .accountWeb(let owner, let url): "accountWeb:\(owner):\(url.absoluteString)"
        case .web(let url): "web:\(url.absoluteString)"
        case .textSize: "textSize"
        case .about: "about"
        case .privacy: "privacy"
        case .terms: "terms"
        case .report(let report): "report:\(report.owner):\(report.url.absoluteString)"
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

/// Platform-neutral pictures and optional motion supplied by their adapter.
struct ViewerRequest: Identifiable {
    let id = UUID()
    let pics: [PicInfo]
    let index: Int
    var motion: PhotoMotion? = nil
    /// The id of the tile it zooms out of, in the media namespace.
    var sourceID: String? = nil
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
private final class RouterState {
    var tab: AppTab = .home
    var paths: [AppTab: [Route]] = [:]
    var showingLogin: Bool = false
    var loginPlatform: SocialPlatform? = nil
    var showingCompose: Bool = false
    var viewer: ViewerRequest? = nil
    var video: VideoRequest? = nil
    var web: WebRequest? = nil
    var repost: RepostRequest? = nil
    var deletion: DeleteRequest? = nil
    var commentComposer: CommentComposerRequest? = nil
    var presentationAccount: String?
}

@MainActor @Observable
final class Router {
    @ObservationIgnored private let shared: RouterState
    let accountKey: String?
    var presentationAccount: String? { shared.presentationAccount }
    init() { shared = RouterState(); accountKey = nil }
    private init(shared: RouterState, account: String) { self.shared = shared; accountKey = account }
    func scoped(_ account: String) -> Router { Router(shared: shared, account: account) }
    var tab: AppTab { get { shared.tab } set { shared.tab = newValue } }
    var paths: [AppTab: [Route]] { get { shared.paths } set { shared.paths = newValue } }
    var showingLogin: Bool { get { shared.showingLogin } set { shared.showingLogin = newValue } }
    var loginPlatform: SocialPlatform? { get { shared.loginPlatform } set { shared.loginPlatform = newValue } }
    var showingCompose: Bool { get { shared.showingCompose } set { shared.presentationAccount = accountKey; shared.showingCompose = newValue } }
    var viewer: ViewerRequest? { get { shared.viewer } set { shared.presentationAccount = accountKey; shared.viewer = newValue } }
    var video: VideoRequest? { get { shared.video } set { shared.presentationAccount = accountKey; shared.video = newValue } }
    var web: WebRequest? { get { shared.web } set { shared.presentationAccount = accountKey; shared.web = newValue } }
    var repost: RepostRequest? { get { shared.repost } set { shared.presentationAccount = accountKey; shared.repost = newValue } }
    var deletion: DeleteRequest? { get { shared.deletion } set { shared.presentationAccount = accountKey; shared.deletion = newValue } }
    var commentComposer: CommentComposerRequest? { get { shared.commentComposer } set { shared.presentationAccount = accountKey; shared.commentComposer = newValue } }
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

    func push(_ route: Route) {
        let target: Route
        if let accountKey, route != .accounts { target = .account(accountKey, route) } else { target = route }
        paths[tab, default: []].append(target)
    }

    func pop() {
        _ = paths[tab]?.popLast()
    }

    /// Opens the results of searching for [query]; `#话题#` searches the topic.
    func openSearch(_ query: String, asGuest: Bool = false) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            push(asGuest ? .web(weiboSearchURL(query)) : .searchResults(query))
        }
    }
}
