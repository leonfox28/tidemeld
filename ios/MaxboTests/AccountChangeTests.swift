import Foundation
import Testing

@testable import Maxbo

/// What another account, or none, starts over.
@MainActor
struct AccountChangeTests {
    @Test func notificationListsStartOver() async {
        let (session, api) = testSession()
        let model = NotificationsModel()
        model.attach(api, session: session)
        let comments = model.commentList(.comments)
        let likes = model.likeList()

        await session.logout()

        #expect(model.comments == nil)
        #expect(model.likes == nil)
        #expect(model.commentList(.comments) !== comments)
        #expect(model.likeList() !== likes)
    }

    @Test func signingOutClosesThePagesOpenInEachTab() async {
        let graph = testGraph()
        graph.router.tab = .notifications
        graph.router.paths = [.home: [.status(id: "1", initial: nil)], .search: [.searchResults("词")]]

        await graph.session.logout()

        let open = graph.router.paths.values.flatMap { $0 }
        #expect(open.isEmpty)
        #expect(graph.router.tab == .home)
    }

    @Test func aLapsedSessionKeepsThemForTheSameAccount() {
        let graph = testGraph()
        graph.router.tab = .notifications
        graph.router.paths = [.home: [.status(id: "1", initial: nil)]]

        graph.session.expire()

        #expect(graph.router.paths[.home]?.count == 1)
        #expect(graph.router.tab == .home)
    }
}
