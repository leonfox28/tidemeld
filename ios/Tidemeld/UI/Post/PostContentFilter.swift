import SwiftUI

/// No hidden content is mounted, so its images, actions and accessibility text stay hidden too.
struct PostContentFilter<Content: View>: View {
    let text: String
    @ViewBuilder let content: () -> Content
    @Environment(AppGraph.self) private var graph

    var body: some View {
        if ContentFilter.matches(text, keywords: graph.settings.settings.filterKeywords) {
            Label("已按本地关键词过滤", systemImage: "line.3.horizontal.decrease.circle")
                .font(.footnote).foregroundStyle(AppTheme.secondary)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHint("可在设置中的内容过滤修改关键词")
        } else {
            content()
        }
    }
}

extension Status {
    var contentFilterText: String {
        [user?.screenName ?? "", plainStatusText(text), retweeted?.contentFilterText ?? ""].joined(separator: "\n")
    }
}

extension Comment {
    var contentFilterText: String {
        ([user?.screenName ?? "", plainStatusText(text)] + replies.map(\.contentFilterText)).joined(separator: "\n")
    }
}

extension XPost {
    var contentFilterText: String {
        [author, handle, text, quote?.post.contentFilterText ?? ""].joined(separator: "\n")
    }
}
