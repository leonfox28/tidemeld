import SwiftUI

/// A status to repost, in the sheet at the root; [quote] is what the text
/// starts as when there is no draft.
struct RepostRequest: Identifiable {
    let id = UUID()
    let status: Status
    let quote: String
    var onReposted: (() -> Void)? = nil
}

/// A status of the user's to delete once they confirm.
struct DeleteRequest: Identifiable {
    let id = UUID()
    let status: Status
    var onDeleted: (() -> Void)? = nil
}

extension AppGraph {
    /// Guests can open the media already supplied by the public feed. Account
    /// actions and further reading start sign-in, without trying private APIs.
    var guestStatusActions: StatusCardActions {
        var actions = statusActions
        actions.onLike = { [router] _ in router.showingLogin = true }
        actions.onOpen = { [router] _ in router.showingLogin = true }
        actions.onExpand = actions.onOpen
        actions.onRepost = actions.onOpen
        actions.onDelete = nil
        actions.onUser = { [router] _ in router.showingLogin = true }
        actions.onPicture = { [router, api] pics, index, _, source in
            router.viewer = ViewerRequest(pics: pics, index: index, motion: weiboPhotoMotion(api: api, statusId: nil), sourceID: source)
        }
        actions.onLink = { [weak self, router] link in
            switch link {
            case .mention: router.showingLogin = true
            case .topic(let topic): router.openSearch("#\(topic)#", asGuest: true)
            default: self?.open(link)
            }
        }
        return actions
    }

    /// What tapping parts of a status card (or a comment) does throughout the
    /// app.
    var statusActions: StatusCardActions {
        let router = router
        let api = api
        return StatusCardActions(
            onOpen: { router.push(.status(id: $0.id, initial: $0)) },
            onLink: { [weak self] link in self?.open(link) },
            onUser: { router.push(.profile(uid: $0.id, initial: $0)) },
            // The detail page has the full text of long posts.
            onExpand: { router.push(.status(id: $0.id, initial: $0)) },
            onPicture: { pics, index, status, source in
                router.viewer = ViewerRequest(pics: pics, index: index, motion: weiboPhotoMotion(api: api, statusId: status?.id), sourceID: source)
            },
            onVideo: { status, index in
                router.video = weiboVideoRequest(api: api, status: status, index: index)
            },
            onRepost: { [weak self] in self?.repost($0) },
            onDelete: { [weak self] in self?.delete($0) })
    }

    func open(_ link: StatusLink) {
        switch link {
        case .web(let url): openExternally(url)
        case .video(let video): router.video = weiboVideoRequest(api: api, link: video)
        // Mentions carry only the name.
        case .mention(let name): router.push(.profileByName(name))
        case .topic(let topic): router.openSearch("#\(topic)#")
        case .image(let url, let pics):
            if pics.isEmpty {
                openExternally(url)
            } else {
                router.viewer = ViewerRequest(pics: pics, index: 0, motion: weiboPhotoMotion(api: api, statusId: nil))
            }
        }
    }

    /// Opens [url] in the user's browser.
    func openExternally(_ url: URL) {
        UIApplication.shared.open(url) { [toasts] opened in
            if !opened { toasts.show("无法打开链接") }
        }
    }

    /// Likes [target], or takes the like back; a refused toggle is explained in
    /// a toast. App-wide: the like goes on, and is set right, whatever page is
    /// left.
    func toggleLike(_ target: LikeTarget, loaded: LikeState) {
        Task {
            do {
                try await likes.toggle(target, loaded: loaded)
            } catch {
                toasts.showError(error, router: router)
            }
        }
    }

    /// Opens a sheet to repost [status], which goes to Weibo when the user taps
    /// 转发. The repost then goes atop the open lists it belongs in, and
    /// [onReposted] is called.
    ///
    /// Reposting a repost starts the text with the chain it carries on, as
    /// weibo.com does: `//@author:their text`.
    func repost(_ status: Status, onReposted: (() -> Void)? = nil) {
        // Where the user asked from: the sheet is for that page, as the Kotlin
        // sheet is in the page's scope.
        let tab = router.tab
        let pages = router.paths[tab] ?? []
        Task {
            var quoted = status
            // Lists cut long posts short, and the chain quotes all of it.
            if status.retweeted != nil, status.plainText == nil {
                do {
                    quoted = try await api.fetchStatus(status.id)
                } catch {
                    toasts.showError(error, router: router)
                    return
                }
                // Left meanwhile: no sheet over whatever page is up now.
                guard router.tab == tab, (router.paths[tab] ?? []) == pages else { return }
            }
            router.repost = RepostRequest(status: status, quote: quoteOf(quoted), onReposted: onReposted)
        }
    }

    /// A repost went out: it goes atop the open lists it belongs in.
    func reposted(_ request: RepostRequest, repost: Status?) {
        if let repost {
            openLists.prependOwn(repost)
            openLists.reposts.forEach(request.status.id) { $0.prepend(repost) }
        }
        toasts.show("转发成功")
        request.onReposted?()
    }

    /// Offers to delete [status], which the user posted, and asks again before
    /// it goes. Once deleted it leaves the open lists of the user's posts, and
    /// [onDeleted] is called, e.g. to leave its detail page.
    func delete(_ status: Status, onDeleted: (() -> Void)? = nil) {
        // Already going: not asked again.
        guard !deletingStatuses.contains(status.id) else { return }
        router.deletion = DeleteRequest(status: status, onDeleted: onDeleted)
    }

    func confirmDelete(_ request: DeleteRequest) {
        let status = request.status
        guard deletingStatuses.insert(status.id).inserted else { return }
        Task {
            defer { deletingStatuses.remove(status.id) }
            do {
                try await api.deleteStatus(status.id)
            } catch {
                toasts.showError(error, router: router)
                return
            }
            openLists.removeOwn(status)
            toasts.show("已删除")
            request.onDeleted?()
        }
    }
}

/// The chain a repost of [status] carries on, empty if it isn't a repost.
private func quoteOf(_ status: Status) -> String {
    guard status.retweeted != nil, let name = status.user?.screenName, let text = status.plainText else {
        return ""
    }
    return "//@\(name):\(text)"
}
