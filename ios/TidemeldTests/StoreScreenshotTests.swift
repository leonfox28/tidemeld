import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Tidemeld

/// Opt-in artifact rendering. No real accounts, network responses or production data.
/// Enable TIDEMELD_STORE_SCREENSHOTS in the test runner's environment, and set
/// TIDEMELD_SCREENSHOT_DIRECTORY to an absolute output directory.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["TIDEMELD_STORE_SCREENSHOTS"] == "1"))
struct StoreScreenshotTests {
    @Test func renderStoreScreenshots() async throws {
        let output = try #require(ProcessInfo.processInfo.environment["TIDEMELD_SCREENSHOT_DIRECTORY"])
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        defer {
            window.isHidden = true
            previousWindow?.makeKeyAndVisible()
        }

        let graph = testGraph(restored: session("7001", name: "示例账号 · 日常", platform: .weibo))
        try graph.accounts.add(.weibo, session: session("7002", name: "示例账号 · 阅读", platform: .weibo))
        try graph.accounts.add(.x, session: session("8001", name: "示例账号 · 灵感", platform: .x))
        _ = graph.accounts.useWeibo("weibo:7001")
        let posts = samplePosts()
        graph.socialFeed = SocialFeedController(accounts: graph.accounts) { account, _ in
            Paged(items: posts.filter { $0.owner == account.id })
        }
        graph.settings.update { $0.themeMode = .light }
        graph.socialFeed.select(.all)
        await graph.socialFeed.waitForIdle()
        #expect(graph.socialFeed.items.count == posts.count)
        let host = UIHostingController(rootView: RootView().environment(graph))
        window.rootViewController = host
        window.makeKeyAndVisible()

        try await capture(window, directory: directory, name: "01-combined-feed")
        graph.settings.update {
            $0.feedSelection = .x
            $0.themeMode = .dark
        }
        graph.socialFeed.select(.x)
        await graph.socialFeed.waitForIdle()
        try await capture(window, directory: directory, name: "02-x-dark")
        graph.settings.update { $0.themeMode = .light }
        graph.router.push(.accounts)
        try await capture(window, directory: directory, name: "03-accounts")
        graph.router.paths = [:]
        graph.router.tab = .settings
        graph.router.push(.textSize)
        try await capture(window, directory: directory, name: "04-text-size")
    }

    private func capture(_ window: UIWindow, directory: URL, name: String) async throws {
        try await Task.sleep(for: .seconds(1))
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        format.opaque = true
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let data = try #require(image.pngData())
        try data.write(to: directory.appendingPathComponent(name + ".png"))
    }

    private func session(_ id: String, name: String, platform: SocialPlatform) -> StoredSession {
        StoredSession(
            account: Account(uid: id, screenName: name),
            cookies: platform == .weibo
                ? ["weibo.com": ["SUB": "synthetic-store-screenshot"]]
                : ["x.com": ["auth_token": "synthetic-store-screenshot", "ct0": "synthetic"]])
    }

    private func samplePosts() -> [FeedPost] {
        let now = Date()
        func weibo(_ id: String, _ name: String, _ text: String, minutes: Int, owner: String = "weibo:7001") -> FeedPost {
            .weibo(owner: owner, Status(
                id: id, user: WeiboUser(id: "sample-" + id, screenName: name),
                createdAt: now.addingTimeInterval(-Double(minutes * 60)), source: "示例内容",
                text: text, repostsCount: 2, commentsCount: 6, likesCount: 18))
        }
        func x(_ id: String, _ name: String, _ text: String, minutes: Int, quote: XQuote? = nil) -> FeedPost {
            .x(owner: "x:8001", XPost(
                id: id, author: name, handle: "sample_" + id, avatar: nil, text: text,
                createdAt: now.addingTimeInterval(-Double(minutes * 60)), pictures: [],
                videoCover: nil, videoURL: nil, quote: quote, originalID: id,
                metrics: XMetrics(likes: 12, reposts: 3, replies: 4)))
        }
        let quote = XPost(
            id: "8010", author: "山海笔记 · 示例", handle: "sample_8010", avatar: nil,
            text: "留一点时间，看看窗外。\n此帖为截图示例。", createdAt: now.addingTimeInterval(-3600),
            pictures: [], videoCover: nil, videoURL: nil, quote: nil, originalID: "8010")
        return [
            weibo("7010", "叠澜 · 示例", "多个社交网络，一个信息流。\n把关注的动态放在一起，按时间慢慢读。\n\n以下账号与帖子均为截图示例。", minutes: 2),
            x("8011", "海风来信 · 示例", "A quiet moment between the waves.\n\n散步时想到的句子，先记下来。\n此帖为截图示例。", minutes: 5),
            weibo("7011", "林间书页 · 示例", "今天读到一句话：生活里细小的发现，也值得认真记录。\n\n你最近在读什么？（示例内容）", minutes: 9, owner: "weibo:7002"),
            x("8012", "周末漫游 · 示例", "把喜欢的句子留在这里。\n此帖为截图示例。", minutes: 12, quote: XQuote(quote)),
            weibo("7012", "日常拾光 · 示例", "一杯茶，一页书，一个安静的下午。\n慢一点，也很好。（示例内容）", minutes: 18),
            x("8013", "留白练习 · 示例", "Less scrolling, more noticing.\n把读到的灵感，带回生活里。\n此帖为截图示例。", minutes: 24),
        ]
    }
}
