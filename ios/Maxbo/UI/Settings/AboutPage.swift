import SwiftUI

let repoURL = URL(string: "https://github.com/leonfox28/maxbo")!
let issuesURL = URL(string: "https://github.com/leonfox28/maxbo/issues")!

// Kept in line with the README.
private let disclaimer = [
    "maxbo 是非官方客户端，与新浪微博及北京微梦创科网络技术有限公司没有任何关联，仅供学习交流。",
    "不收费、不接受赞助，不提供去广告、批量下载、会员内容等功能。",
    "使用非官方客户端可能导致账号被风控或受到限制，风险由使用者自行承担。请遵守《微博服务使用协议》。",
    "如权利人认为本项目不妥，请到项目主页提 issue 联系，我们会及时处理。",
]

private let privacy = [
    "登录在微博官方网页登录页中完成，maxbo 接触不到你的密码。",
    "登录状态只保存在本机（iOS 钥匙串），退出登录时清除。",
    "没有服务器，没有统计、埋点或崩溃上报，不收集任何数据；应用只和微博的服务器通信。",
    "只在你操作时请求微博，不在后台轮询或预取。",
]

/// The app's version, as in app/build.gradle.kts.
var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
}

/// What maxbo is, the disclaimer, the privacy statement and licences.
struct AboutPage: View {
    @Environment(AppGraph.self) private var graph

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    Text("maxbo").font(.largeTitle.weight(.semibold)).foregroundStyle(AppTheme.primary)
                    Text("版本 \(appVersion)").font(.subheadline).foregroundStyle(AppTheme.secondary)
                    Text("开源、非商业的第三方微博阅读客户端").font(.subheadline).padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            bullets("声明", disclaimer)
            bullets("隐私", privacy)
            Section {
                Button {
                    graph.openExternally(repoURL)
                } label: {
                    Label { Text("项目主页"); Text(repoURL.absoluteString) } icon: {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                    }
                }
                Button {
                    graph.openExternally(issuesURL)
                } label: {
                    Label { Text("问题反馈"); Text("在 GitHub 上提 issue") } icon: {
                        Image(systemName: "exclamationmark.bubble")
                    }
                }
                NavigationLink(value: Route.licenses) {
                    Label { Text("开源许可"); Text("maxbo 以 GPL-3.0 发布") } icon: {
                        Image(systemName: "doc.text")
                    }
                }
            }
            .foregroundStyle(AppTheme.foreground)
            .listRowBackground(AppTheme.surface)
        }
        .appListStyle()
        .tabBarFollowsScroll()
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bullets(_ title: String, _ items: [String]) -> some View {
        Section(title) {
            ForEach(items, id: \.self) { item in
                Text(item).font(.subheadline)
            }
        }
        .listRowBackground(AppTheme.surface)
    }
}

/// maxbo's licence. The iOS app is built on Apple's frameworks alone, so there
/// are no third-party libraries to list.
struct LicensesPage: View {
    @State private var text: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("maxbo 以 GNU General Public License v3.0 发布。iOS 版只用了系统自带的框架，没有第三方库。")
                    .font(.subheadline)
                if let text {
                    Text(text).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
            .foregroundStyle(AppTheme.foreground)
            .padding(16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .tabBarFollowsScroll()
        .appBackground()
        .navigationTitle("开源许可")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            text = Bundle.main.url(forResource: "LICENSE", withExtension: nil)
                .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        }
    }
}
