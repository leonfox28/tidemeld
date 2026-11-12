import SwiftUI

struct ProfileAction: Identifiable {
    let id: String
    let title: String
    var symbol: String = "person.badge.plus"
    var destructive = false
    var confirmation: String? = nil
    let perform: () async throws -> Void
}

struct ProfileActions {
    var primary: ProfileAction? = nil
    var more: [ProfileAction] = []
    var busy = false
}

/// Buttons and confirmation UI are shared; action semantics and requests belong to adapters.
struct SocialProfileActions: View {
    let actions: ProfileActions
    var menuLabel = "更多用户操作"
    @Environment(AppGraph.self) private var graph
    @State private var confirming: ProfileAction?
    @State private var running = false

    var body: some View {
        HStack(spacing: 4) {
            if actions.busy {
                ProgressView().controlSize(.small).frame(minWidth: 72, minHeight: 36)
                    .accessibilityLabel("正在更新关系")
            } else if let action = actions.primary {
                Button(action.title) { select(action) }
                    .font(.subheadline).buttonStyle(.bordered).controlSize(.small)
                    .fixedSize(horizontal: true, vertical: false)
            }
            if !actions.more.isEmpty {
                Menu {
                    ForEach(actions.more) { action in
                        Button(role: action.destructive ? .destructive : nil) {
                            select(action)
                        } label: {
                            Label(action.title, systemImage: action.symbol)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 36, height: 36).contentShape(Rectangle())
                }
                .accessibilityLabel(menuLabel)
                .disabled(actions.busy || running)
            }
        }
        .confirmationDialog(
            confirming?.title ?? "",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible, presenting: confirming
        ) { action in
            Button(action.title, role: action.destructive ? .destructive : nil) { run(action) }
            Button("取消", role: .cancel) {}
        } message: { action in
            Text(action.confirmation ?? "")
        }
    }

    private func select(_ action: ProfileAction) {
        guard !actions.busy && !running else { return }
        if action.confirmation != nil { confirming = action } else { run(action) }
    }
    private func run(_ action: ProfileAction) {
        confirming = nil
        guard !running else { return }
        running = true
        Task {
            defer { running = false }
            do { try await action.perform() } catch { graph.toasts.showError(error, router: graph.router) }
        }
    }
}

/// Builds the same relationship controls from the capabilities a platform actually supplies.
func profileActions(
    name: String, state: ProfileRelationshipState,
    follow: @escaping (Bool) async throws -> Void,
    block: ((Bool) async throws -> Void)?,
    reposts: ((Bool) async throws -> Void)?,
    refresh: @escaping () async throws -> Void
) -> ProfileActions {
    let value = state.value
    if state.needsRefresh {
        return ProfileActions(
            primary: ProfileAction(id: "refresh", title: "刷新状态", symbol: "arrow.clockwise", perform: refresh),
            busy: state.busy)
    }
    var result = ProfileActions(busy: state.busy)
    if value.blocking != true {
        let removing = value.following || value.requested
        result.primary = ProfileAction(
            id: "follow", title: value.requested ? "取消申请" : removing ? "取消关注" : "关注",
            confirmation: removing ? "确定\(value.requested ? "取消关注申请" : "取消关注")“\(name)”？" : nil,
            perform: { try await follow(!removing) })
    }
    if let block, let blocked = value.blocking {
        result.more.append(
            ProfileAction(
                id: "block", title: blocked ? "取消拉黑" : "拉黑", symbol: "hand.raised", destructive: !blocked,
                confirmation: blocked ? "取消拉黑“\(name)”？不会自动重新关注。" : "确定拉黑“\(name)”？这也会解除关注关系。",
                perform: { try await block(!blocked) }))
    }
    if value.following, value.blocking != true, let enabled = value.showsReposts, let reposts {
        result.more.append(
            ProfileAction(
                id: "reposts", title: enabled ? "关闭转帖" : "开启转帖", symbol: "arrow.2.squarepath",
                perform: { try await reposts(!enabled) }))
    }
    return result
}
