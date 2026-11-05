import SwiftUI

/// Prepare the selected identity before the first browser request.
struct AccountWebPage: View {
    let owner: String
    let url: URL
    @Environment(AppGraph.self) private var graph
    @State private var ready = false
    @State private var error: String?

    var body: some View {
        Group {
            if ready {
                InAppBrowser(url: url)
            } else if let error {
                ContentUnavailableView(error, systemImage: "person.crop.circle.badge.exclamationmark")
            } else {
                ProgressView("准备账号")
            }
        }
        .task(id: owner) {
            do {
                try await graph.accounts.prepareBrowser(owner)
                try Task.checkCancellation()
                ready = true
            } catch {
                if !WeiboError.isCancellation(error) { self.error = "账号不可用，请返回账号管理重新登录" }
            }
        }
    }
}
