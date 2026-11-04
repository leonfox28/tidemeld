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
}
