import Foundation
import Testing

@testable import Tidemeld

extension FakeWeiboTests {
@MainActor @Suite
struct GuestBrowsingTests {
    @Test func guestsCanReadHotSearchWithoutSigningInOrSendingAnAccountCookie() async throws {
        FakeWeibo.reset { _ in
            .init(body: ##"{"ok":1,"data":{"realtime":[{"word":"示例热搜","word_scheme":"#示例热搜#","realpos":1}],"hotgovs":[]}}"##)
        }
        let (session, api) = testSession(restored: nil, configuration: FakeWeibo.configuration)

        let hot = try await api.fetchHotSearch()

        #expect(hot.items.map(\.word) == ["示例热搜"])
        #expect(session.state == .signedOut(expired: false))
        #expect(FakeWeibo.requests.map { $0.url?.path } == ["/ajax/side/hotSearch"])
        #expect(FakeWeibo.requests.first?.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test(arguments: ["  天气 & 日落  ", "#示例话题#"])
    func guestSearchUsesThePublicWebPageAndSignedInSearchStaysNative(_ input: String) throws {
        let router = Router()
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)

        router.openSearch(input, asGuest: true)
        guard case .web(let url) = router.paths[.home]?.last else {
            Issue.record("A guest search must not open the authenticated native results page")
            return
        }
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.host == "m.weibo.cn")
        #expect(parts.path == "/search")
        #expect(parts.queryItems?.first { $0.name == "q" }?.value == query)
        #expect(parts.queryItems?.first { $0.name == "containerid" }?.value == (query.hasPrefix("#") ? "231522" : "100103"))

        router.openSearch(input)
        #expect(router.paths[.home]?.last == .searchResults(query))
    }

    @Test func anEmptyGuestSearchDoesNotNavigate() {
        let router = Router()
        router.openSearch(" \n ", asGuest: true)
        #expect(router.paths.isEmpty)
    }
}
}
