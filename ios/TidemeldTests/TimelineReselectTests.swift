import SwiftUI
import Testing
import UIKit

@testable import Tidemeld

@MainActor @Suite(.serialized)
struct TimelineReselectTests {
    @Test(arguments: [FeedSelection.all, .weibo, .x], [false, true])
    func homeTapReturnsToTopThenShowsAndCompletesEachRefresh(
        selection: FeedSelection, insertsNewPost: Bool
    ) async throws {
        let graph = testGraph()
        try graph.accounts.add(
            .x,
            session: StoredSession(
                account: Account(uid: "9"), cookies: ["x.com": ["auth_token": "synthetic"]]))
        graph.settings.update { $0.feedSelection = selection }
        var requests = 0
        var revisions: [String: Int] = [:]
        graph.socialFeed = SocialFeedController(accounts: graph.accounts) { account, cursor in
            #expect(cursor == nil, "Revealing and retracting refresh must not load older posts")
            requests += 1
            revisions[account.id, default: 0] += 1
            let newest = insertsNewPost ? 29 + revisions[account.id, default: 0] : 30
            try await Task.sleep(for: .milliseconds(600))
            return Paged(
                items: (1...newest).reversed().map { index in
                    let text = "合成动态 \(index)" + (index > 30 ? String(repeating: "\n新增内容", count: 3) : "")
                    if account.platform == .weibo {
                        return .weibo(owner: account.id, Status(id: "\(index)", text: text))
                    }
                    return .x(
                        owner: account.id,
                        XPost(
                            id: "\(index)", author: "示例作者", handle: "fixture", avatar: nil,
                            text: text, createdAt: nil, pictures: [], videoCover: nil,
                            videoURL: nil, quote: nil, originalID: "\(index)"))
                }, nextCursor: "more")
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
            try await Task.sleep(for: .milliseconds(250))
            #expect(control.isRefreshing, "Another tap must leave the current refresh running")
            let frames = RefreshFrameRecorder(scroll: scroll)
            defer { frames.stop() }
            await graph.socialFeed.waitForIdle()
            try await Task.sleep(for: .milliseconds(800))
            frames.stop()
            #expect(requests == initialRequests * (refresh + 1))
            #expect(!control.isRefreshing)
            #expect(abs(scroll.contentOffset.y + scroll.adjustedContentInset.top) <= 4)
            #expect(frames.offsets.count > 5)
            #expect(
                frames.largestReversal <= 4,
                "Refresh completion must settle without bouncing: \(frames.offsets.map { $0.rounded() })")
            let newest = insertsNewPost ? 30 + refresh : 30
            #expect(graph.socialFeed.items.first?.id == "\(selection == .x ? "x" : "weibo"):\(newest)")
        }
    }

    private func refreshingScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.refreshControl != nil { return scroll }
        return view.subviews.lazy.compactMap { refreshingScrollView(in: $0) }.first
    }
}

@MainActor private final class RefreshFrameRecorder: NSObject {
    private let scroll: UIScrollView
    private var link: CADisplayLink?
    private(set) var offsets: [CGFloat] = []

    init(scroll: UIScrollView) {
        self.scroll = scroll
        super.init()
        link = CADisplayLink(target: self, selector: #selector(sample))
        link?.add(to: .main, forMode: .common)
    }

    func stop() { link?.invalidate() }

    var largestReversal: CGFloat {
        var highest = offsets.first ?? 0
        var reversal: CGFloat = 0
        for offset in offsets {
            highest = max(highest, offset)
            reversal = max(reversal, highest - offset)
        }
        return reversal
    }

    @objc private func sample() {
        offsets.append((scroll.layer.presentation() ?? scroll.layer).bounds.origin.y)
    }
}
