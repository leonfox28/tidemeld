import SwiftUI

/// One profile layout. Adapters supply presentation, paging and account-bound actions.
struct SocialProfilePage<Item: Sendable, Badge: View, Details: View, Row: View>: View {
    let title: String
    let profile: ProfilePresentation
    let posts: PagedList<Item>?
    let failure: AppFailure?
    let emptyText: String
    let retry: () -> Void
    let refresh: () async throws -> Void
    var actions: ProfileActions? = nil
    @ViewBuilder let badge: () -> Badge
    @ViewBuilder let details: () -> Details
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        Group {
            if let posts {
                SocialContentList(refresh: refresh) {
                    SocialProfileHeader(
                        profile: profile, onRetry: retry, actions: actions, badge: badge, details: details
                    )
                    .readingWidth().plainRow()
                    PagedRows(list: posts, emptyText: emptyText) { post in
                        row(post).readingWidth().statusRow()
                    }
                }
            } else if let failure {
                ErrorRetry(error: failure, onRetry: retry)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
