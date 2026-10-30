import SwiftUI

/// The 我 tab: the account, settings, and signing out. Settings stay within
/// reach before logging in.
struct MePage: View {
    @Environment(AppGraph.self) private var graph
    @State private var confirmingLogout = false

    var body: some View {
        let router = graph.router
        List {
            switch graph.session.state {
            case .signedOut(let expired):
                Section {
                    LoginPrompt(expired: expired)
                }
            case .signedIn(let account):
                Section {
                    Button {
                        router.push(
                            .profile(uid: account.uid, initial: account.screenName.map { WeiboUser(id: account.uid, screenName: $0) }))
                    } label: {
                        HStack(spacing: 12) {
                            UserAvatar(user: nil, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.screenName ?? "微博用户").font(.headline)
                                Text("UID \(account.uid)").font(.caption).foregroundStyle(AppTheme.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(AppTheme.surface)
            }
            Section {
                NavigationLink(value: Route.settings) { Label("设置", systemImage: "gearshape") }
                #if DEBUG
                NavigationLink(value: Route.diagnostics) { Label("开发者诊断", systemImage: "ladybug") }
                #endif
            }
            .listRowBackground(AppTheme.surface)
            if graph.session.state.uid != nil {
                Section {
                    Button("退出登录", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        confirmingLogout = true
                    }
                }
                .listRowBackground(AppTheme.surface)
            }
        }
        .appListStyle()
        .navigationTitle("我")
        .alert("退出登录", isPresented: $confirmingLogout) {
            Button("退出", role: .destructive) { Task { await graph.session.logout() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清除本机保存的微博登录状态。")
        }
    }
}
