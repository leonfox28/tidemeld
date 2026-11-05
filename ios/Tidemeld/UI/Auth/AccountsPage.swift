import SwiftUI

struct LoginFlowPage: View {
    @Environment(AppGraph.self) private var graph
    @Environment(\.dismiss) private var dismiss
    @State private var platform: SocialPlatform?
    var body: some View {
        Group {
            if let platform {
                LoginPage(platform: platform)
            } else {
                NavigationStack {
                    List(SocialPlatform.allCases) { platform in
                        Button {
                            self.platform = platform
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(platform.label).font(.headline)
                                Text("使用官方网页登录，可添加多个账号").font(.footnote).foregroundStyle(AppTheme.secondary)
                            }.padding(.vertical, 8)
                        }
                    }
                    .navigationTitle("选择登录平台")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
                    }
                }
            }
        }
        .onAppear { platform = graph.router.loginPlatform }
        .onDisappear { graph.router.loginPlatform = nil }
    }
}

struct AccountsPage: View {
    @Environment(AppGraph.self) private var graph
    @State private var removing: SocialAccount?
    @State private var error: String?
    var body: some View {
        List {
            Section {
                Text("已登录账号的信息流会一起显示。移除账号仅清除本机登录状态。")
                    .font(.footnote).foregroundStyle(AppTheme.secondary)
                if let error { Text(error).foregroundStyle(.red) }
            }
            ForEach(SocialPlatform.allCases) { platform in
                Section(platform.label) {
                    ForEach(graph.accounts.accounts.filter { $0.platform == platform }) { account in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(account.name).font(.headline)
                            Text(
                                account.expired
                                    ? "登录已过期"
                                    : (platform == .weibo
                                        && graph.session.state.uid == account.session.account.uid
                                        ? "已登录 · 微博功能当前账号" : "已登录")
                            )
                            .font(.footnote).foregroundStyle(AppTheme.secondary)
                            HStack {
                                if account.expired {
                                    Button("重新登录") { login(platform) }
                                } else if platform == .weibo {
                                    Button("使用") { graph.accounts.useWeibo(account.id) }
                                }
                                Spacer()
                                Button("移除", role: .destructive) { removing = account }
                            }.buttonStyle(.borderless)
                        }.padding(.vertical, 5)
                    }
                    Button("添加\(platform.label)账号", systemImage: "plus") { login(platform) }
                }
            }
        }
        .appListStyle()
        .navigationTitle("账号管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("添加账号", systemImage: "plus") {
                    graph.router.loginPlatform = nil
                    graph.router.showingLogin = true
                }
            }
        }
        .confirmationDialog(
            "移除账号", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            presenting: removing
        ) { account in
            Button("移除 \(account.name)", role: .destructive) {
                removing = nil
                Task {
                    do { try await graph.accounts.remove(account.id) } catch {
                        self.error = loadErrorMessage(error)
                    }
                }
            }
        } message: { account in
            Text("移除 \(account.platform.label) · \(account.name)？其他账号保持登录。")
        }
    }
    private func login(_ platform: SocialPlatform) {
        graph.router.loginPlatform = platform
        graph.router.showingLogin = true
    }
}
