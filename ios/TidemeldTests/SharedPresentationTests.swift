import Foundation
import Testing

@testable import Tidemeld

@Suite struct SharedPresentationTests {
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
        let list = PagedList<String>(fetch: { _ in
            if fail { throw OtherPlatformFailure() }
            return Paged(items: ["synthetic"], nextCursor: nil)
        }, id: { $0 })
        list.start()
        for _ in 0..<100 {
            if case .failed = list.state { break }
            await Task.yield()
        }
        guard case .failed(let failure) = list.state else { Issue.record("Expected the independent failure"); return }
        #expect(failure.message == "合成平台需要登录")
        #expect(failure.recovery == .signIn)
        fail = false
        try await list.refresh()
        #expect(list.items == ["synthetic"])
        #expect(AppFailure.of(CancellationError()).isCancelled)
    }
}
