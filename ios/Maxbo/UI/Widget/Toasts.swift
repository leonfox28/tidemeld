import Observation
import SwiftUI

/// A short message over the app, such as the outcome of something the user
/// did, which goes by itself; with an action, such as taking Weibo's security
/// check.
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

@MainActor @Observable
final class Toasts {
    private(set) var current: Toast?
    @ObservationIgnored private var hide: Task<Void, Never>?

    func show(_ message: String, actionLabel: String? = nil, action: (() -> Void)? = nil) {
        let toast = Toast(message: message, actionLabel: actionLabel, action: action)
        current = toast
        hide?.cancel()
        hide = Task {
            try? await Task.sleep(for: .seconds(action == nil ? 2.5 : 5))
            if current == toast { current = nil }
        }
    }

    /// Tells the user why something they did failed; when Weibo wants a
    /// security check first, offers to take it (they then try again
    /// themselves).
    func showError(_ error: Error, router: Router) {
        let error = WeiboError.of(error)
        if let url = error.captchaURL {
            show(error.message, actionLabel: "去验证") { router.web = WebRequest(url: url) }
        } else {
            show(error.message)
        }
    }

    func dismiss() {
        current = nil
    }
}

/// The current toast, in glass, above the bottom of the screen.
struct ToastHost: View {
    @Environment(Toasts.self) private var toasts

    var body: some View {
        VStack {
            Spacer()
            if let toast = toasts.current {
                HStack(spacing: 12) {
                    Text(toast.message)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                    if let label = toast.actionLabel, let action = toast.action {
                        Button(label) {
                            toasts.dismiss()
                            action()
                        }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, 24)
                .padding(.bottom, 72)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture { toasts.dismiss() }
                .id(toast.id)
            }
        }
        .animation(.spring(duration: 0.35), value: toasts.current)
        .allowsHitTesting(toasts.current != nil)
    }
}
