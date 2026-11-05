import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Tidemeld

@Suite struct SharedPresentationTests {
    @MainActor @Test(arguments: [1, 50])
    func addingConversationContextKeepsTheVisiblePostStill(parentLines: Int) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let fixture = ConversationFixture(parentLines: parentLines)
        let host = UIHostingController(
            rootView: ConversationFixturePage(fixture: fixture).environment(testGraph(restored: nil)))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousWindow?.makeKeyAndVisible()
        }
        try await Task.sleep(for: .milliseconds(600))
        let before = try #require(fixture.probe)
        let recorder = ConversationFrameRecorder(view: before, window: window)
        defer { recorder.stop() }
        try await Task.sleep(for: .milliseconds(200))
        let initialY = try #require(recorder.positions.last)
        recorder.reset()
        fixture.loaded = true
        try await Task.sleep(for: .seconds(1))
        #expect(recorder.positions.count >= 5)
        let excursion = recorder.positions.map { abs($0 - initialY) }.max() ?? .infinity
        #expect(
            excursion < 3,
            "Context insertion moved the visible post by \(excursion) points: initial \(initialY), frames \(Array(Set(recorder.positions.map { $0.rounded() })).sorted())"
        )
        var ancestor = before.superview
        while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
        let scroll = try #require(ancestor as? UIScrollView)
        let offset = scroll.contentOffset
        let reveal = min(12, offset.y + scroll.adjustedContentInset.top)
        #expect(reveal > 0, "The reply must have scrollable context above it")
        scroll.setContentOffset(CGPoint(x: offset.x, y: offset.y - reveal), animated: false)
        try await Task.sleep(for: .milliseconds(100))
        let browsedY = before.convert(.zero, to: window).y
        #expect(abs(browsedY - initialY - reveal) < 3, "Browsing context must not snap back to the post")
        fixture.responsesLoaded = true
        recorder.reset()
        try await Task.sleep(for: .milliseconds(300))
        #expect(recorder.positions.allSatisfy { abs($0 - browsedY) < 3 })
    }

    @Test func xTextKeepsLiteralContentAndSeparatesLinkDestinations() {
        let text = "😀 <tag> @fixture #中文话题 email@example.com https://example.com/a_(b))."
        let runs = xTextSegments(text)
        let plain = runs.map { run in
            switch run {
            case .plain(let value), .link(let value, _, _): value
            default: ""
            }
        }.joined()
        #expect(plain == text)
        let links = runs.compactMap { run -> String? in
            if case .link(_, let value, _) = run { return value }
            return nil
        }
        #expect(links.count == 3)
        #expect(links[0] == "https://x.com/fixture")
        #expect(URLComponents(string: links[1])?.queryItems?.first?.value == "#中文话题")
        #expect(links[2] == "https://example.com/a_(b)")
    }

    @MainActor @Test func paginationRetainsFailuresFromAnIndependentPlatform() async throws {
        struct OtherPlatformFailure: UserFacingFailure {
            var appFailure: AppFailure { AppFailure(message: "合成平台需要登录", recovery: .signIn) }
        }
        var fail = true
        let list = PagedList<String>(
            fetch: { _ in
                if fail { throw OtherPlatformFailure() }
                return Paged(items: ["synthetic"], nextCursor: nil)
            }, id: { $0 })
        list.start()
        for _ in 0..<100 {
            if case .failed = list.state { break }
            await Task.yield()
        }
        guard case .failed(let failure) = list.state else {
            Issue.record("Expected the independent failure")
            return
        }
        #expect(failure.message == "合成平台需要登录")
        #expect(failure.recovery == .signIn)
        fail = false
        try await list.refresh()
        #expect(list.items == ["synthetic"])
        #expect(AppFailure.of(CancellationError()).isCancelled)
    }
}

@MainActor @Observable private final class ConversationFixture {
    let parentLines: Int
    var loaded = false
    var responsesLoaded = false
    init(parentLines: Int) { self.parentLines = parentLines }
    @ObservationIgnored weak var probe: UIView?
}

private struct ConversationFixturePage: View {
    let fixture: ConversationFixture
    var body: some View {
        NavigationStack {
            PostDetailLayout(
                actions: nil, refresh: {}, initialFocus: "focal",
                context: {
                    if fixture.loaded {
                        Text(String(repeating: "合成上文\n", count: fixture.parentLines)).plainRow().id("ancestor")
                    }
                },
                post: {
                    Text("当前回复").frame(maxWidth: .infinity, minHeight: fixture.loaded ? 180 : 220)
                        .background(ConversationProbe(fixture: fixture))
                        .plainRow()
                },
                responseHeader: { Text("评论 0") },
                responses: {
                    if fixture.responsesLoaded {
                        ForEach(0..<20) { index in
                            Text("合成评论 \(index)").frame(height: 80).responseRow()
                        }
                    } else {
                        Text("还没有评论").frame(height: 80).plainRow()
                    }
                }
            ).navigationTitle("帖子").navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ConversationProbe: UIViewRepresentable {
    let fixture: ConversationFixture
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        fixture.probe = view
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

@MainActor private final class ConversationFrameRecorder: NSObject {
    private weak var view: UIView?
    private weak var window: UIWindow?
    private var displayLink: CADisplayLink?
    private(set) var positions: [CGFloat] = []
    init(view: UIView, window: UIWindow) {
        self.view = view
        self.window = window
        super.init()
        let link = CADisplayLink(target: self, selector: #selector(sample))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }
    func stop() { displayLink?.invalidate() }
    func reset() { positions.removeAll() }
    private var currentPosition: CGFloat? {
        guard let view, let window else { return nil }
        return view.convert(.zero, to: window).y
    }
    @objc private func sample() {
        if let currentPosition { positions.append(currentPosition) }
    }
}
