import SwiftUI
import Testing
import UIKit

@testable import Tidemeld

@MainActor @Suite(.serialized)
struct TimelineReselectTests {
    @Test(arguments: [FeedSelection.all, .weibo, .x])
    func homeTapReturnsToTopThenShowsAndCompletesEachRefresh(selection: FeedSelection) async throws {
        let graph = testGraph()
        try graph.accounts.add(
            .x, session: StoredSession(account: Account(uid: "9"), cookies: ["x.com": ["auth_token": "synthetic"]]))
        graph.settings.update { $0.feedSelection = selection }
        var requests = 0
        graph.socialFeed = SocialFeedController(accounts: graph.accounts) { account, _ in
            requests += 1
            try await Task.sleep(for: .milliseconds(600))
            return Paged(items: (1...30).map { index in
                if account.platform == .weibo {
                    return .weibo(owner: account.id, Status(id: "\(index)", text: "合成微博 \(index)"))
                }
                return .x(
                    owner: account.id,
                    XPost(
                        id: "\(index)", author: "示例作者", handle: "fixture", avatar: nil,
                        text: "合成动态 \(index)", createdAt: nil, pictures: [], videoCover: nil,
                        videoURL: nil, quote: nil, originalID: "\(index)"))
            })
        }
        graph.socialFeed.select(selection)
        await graph.socialFeed.waitForIdle()
        let initialRequests = requests

        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: RootView().environment(graph))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousWindow?.makeKeyAndVisible()
        }
        try await Task.sleep(for: .milliseconds(600))
        let scroll = try #require(refreshingScrollView(in: host.view))
        let control = try #require(scroll.refreshControl)
        scroll.setContentOffset(CGPoint(x: 0, y: 800), animated: false)
        try await Task.sleep(for: .milliseconds(600))
        #expect(scroll.contentOffset.y + scroll.adjustedContentInset.top > 4)

        graph.router.selection.wrappedValue = .home
        try await Task.sleep(for: .milliseconds(800))
        #expect(abs(scroll.contentOffset.y + scroll.adjustedContentInset.top) <= 4)
        #expect(requests == initialRequests, "Returning to the top must not refresh yet")
        #expect(!control.isRefreshing)

        for refresh in 1...2 {
            graph.router.selection.wrappedValue = .home
            try await Task.sleep(for: .milliseconds(250))
            #expect(control.isRefreshing, "Each tap at the top must show the native refresh indicator")
            #expect(requests > initialRequests * refresh)
            graph.router.selection.wrappedValue = .home
            try await Task.sleep(for: .milliseconds(100))
            #expect(control.isRefreshing, "Another tap must leave the current refresh running")
            await graph.socialFeed.waitForIdle()
            try await Task.sleep(for: .milliseconds(800))
            #expect(requests == initialRequests * (refresh + 1))
            #expect(!control.isRefreshing)
            #expect(abs(scroll.contentOffset.y + scroll.adjustedContentInset.top) <= 4)
        }
    }

    private func refreshingScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.refreshControl != nil { return scroll }
        return view.subviews.lazy.compactMap { refreshingScrollView(in: $0) }.first
    }
}
