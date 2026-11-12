import SwiftUI

enum ContentBlock {
    static func key(owner: String, user: String) -> String { "\(owner)/\(user)" }
    static func hides(_ users: [String], owner: String?, blocked: Set<String>) -> Bool {
        guard let owner else { return false }
        return users.contains { blocked.contains(key(owner: owner, user: $0)) }
    }
}

extension SettingsController {
    func recordBlock(owner: String, user: String, blocked: Bool) {
        let key = ContentBlock.key(owner: owner, user: user)
        update { if blocked { $0.blockedUsers.insert(key) } else { $0.blockedUsers.remove(key) } }
    }
}

enum WeiboReportKind: String { case post = "1", comment = "2", user = "3" }

func weiboReportURL(id: String, kind: WeiboReportKind) -> URL {
    var url = URLComponents(string: "https://service.account.weibo.com/reportspamobile")!
    url.queryItems = [URLQueryItem(name: "rid", value: id), URLQueryItem(name: "type", value: kind.rawValue)]
    return url.url!
}

struct PlatformReport: Hashable {
    let owner: String
    let url: URL
    let instructions: String
}

struct PlatformReportPage: View {
    let report: PlatformReport
    var body: some View {
        VStack(spacing: 0) {
            Text(report.instructions)
                .font(.footnote).foregroundStyle(AppTheme.secondary)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.elevated)
            AccountWebPage(owner: report.owner, url: report.url)
        }
    }
}

extension AppGraph {
    var weiboContentOwner: String? { session.state.uid.map { "weibo:\($0)" } }

    func reportAction(owner: String?, url: URL, instructions: String) -> ProfileAction {
        let account = owner.flatMap { accounts.find($0) }
        return ProfileAction(id: "report", title: "举报", symbol: "flag", perform: { [self] in
            guard let owner, let account, !account.expired else {
                router.loginPlatform = owner?.hasPrefix("x:") == true ? .x : .weibo
                router.showingLogin = true
                return
            }
            guard accounts.find(owner)?.revision == account.revision else { throw WeiboError.sessionExpired }
            router.push(.report(PlatformReport(owner: owner, url: url, instructions: instructions)))
        })
    }

    func weiboReportAction(id: String, kind: WeiboReportKind) -> ProfileAction {
        reportAction(owner: weiboContentOwner, url: weiboReportURL(id: id, kind: kind),
            instructions: "请在微博官方页面选择举报原因并提交。处理结果由微博通知；打开此页面不表示举报已提交。")
    }

    func weiboSafetyActions(id: String, kind: WeiboReportKind, user: WeiboUser?) -> ProfileActions {
        var result = ProfileActions(more: [weiboReportAction(id: id, kind: kind)])
        if let user, let owner = weiboContentOwner, user.id != session.state.uid,
           accounts.find(owner)?.expired == false {
            let controls = WeiboProfileControls(self)
            result.more.append(ProfileAction(id: "block", title: "拉黑此用户", symbol: "hand.raised", destructive: true,
                confirmation: "用当前来源账号拉黑“\(user.screenName)”？平台确认后，叠澜会立即隐藏此账号下该用户的内容，并解除关注关系。",
                perform: { try await controls.blockUser(user.id) }))
        }
        return result
    }

    func xReportAction(owner: String, url: URL) -> ProfileAction {
        reportAction(owner: owner, url: url,
            instructions: "请在下方 X 原帖或用户主页的“⋯”菜单中选择“举报 / Report”，完成原因选择和提交。处理结果由 X 通知。")
    }

    func xProfileActions(_ owner: String, user: XProfileUser, failed: Bool) -> ProfileActions? {
        var result = xInteractions.relationshipActions(owner, user: user, failed: failed) ?? ProfileActions()
        if let handle = user.handle, let url = URL(string: "https://x.com/\(handle)") {
            result.more.append(xReportAction(owner: owner, url: url))
        }
        return result
    }

    func xSafetyActions(post: XPost, owner: String) -> ProfileActions {
        var result = ProfileActions(more: [xReportAction(owner: owner, url: post.url)])
        if let uid = post.authorID, let account = accounts.find(owner), !account.expired,
           uid != account.session.account.uid {
            result.more.append(ProfileAction(id: "block", title: "拉黑此用户", symbol: "hand.raised", destructive: true,
                confirmation: "用当前来源账号拉黑“\(post.author)”？平台确认后，叠澜会立即隐藏此账号下该用户的内容，并解除关注关系。",
                perform: { [xInteractions] in
                    try await xInteractions.blockUser(owner, user: post.profileUser, revision: account.revision)
                }))
        }
        return result
    }
}

extension Status {
    var contentAuthorIDs: [String] { [user?.id].compactMap { $0 } + (retweeted?.contentAuthorIDs ?? []) }
}
extension Comment {
    var contentAuthorIDs: [String] { [user?.id].compactMap { $0 } + replies.flatMap(\.contentAuthorIDs) }
}
extension XPost {
    var contentAuthorIDs: [String] { [authorID, repostedByID].compactMap { $0 } + (quote?.post.contentAuthorIDs ?? []) }
}
