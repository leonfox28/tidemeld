import SwiftUI
import UIKit
import WebKit

extension EnvironmentValues {
    /// Set by the navigation stack so covered pages keep their own scroll
    /// state without imposing toolbar preferences on the page above them.
    @Entry var isCurrentNavigationPage = true
}

/// Whether bars that give way to reading show, as the content scrolls: they go
/// as it scrolls on (the finger going up) and come back as it scrolls back,
/// once it has moved [threshold] one way, so a nudge leaves them as they are;
/// at the top they always show. The Android app's bars do the same.
struct ScrollHider: Equatable {
    var threshold: CGFloat = 24
    private(set) var visible = true
    /// Where the content was when the bars last changed, or the scroll last
    /// turned.
    private var anchor: CGFloat = 0
    private var last: CGFloat = 0
    /// The insets above and below the content, which bars change.
    private var top: CGFloat = 0
    private var bottom: CGFloat = 0

    /// Where the content is: how far it has scrolled from its top
    /// ([ScrollGeometry.offsetFromTop]), and the insets above and below it.
    struct Position: Hashable {
        var offset: CGFloat
        var top: CGFloat = 0
        var bottom: CGFloat = 0
    }

    /// Takes the content's new offset from its top.
    mutating func scrolled(to offset: CGFloat) {
        defer { last = offset }
        if offset <= 0 {
            anchor = offset
            visible = true
            return
        }
        // A turn starts measuring again from where it turned.
        if (offset > last) != (last > anchor) { anchor = last }
        let moved = offset - anchor
        if moved > threshold, visible {
            visible = false
            anchor = offset
        } else if moved < -threshold, !visible {
            visible = true
            anchor = offset
        }
    }

    /// Takes the content's new position. A bar coming or going changes the
    /// insets, which can move the content without the user scrolling it, so
    /// that doesn't count.
    mutating func scrolled(to position: Position) {
        if position.top != top || position.bottom != bottom {
            (top, bottom) = (position.top, position.bottom)
            anchor = position.offset
            last = position.offset
        }
        scrolled(to: position.offset)
    }

    /// Shows the bars, and measures again from where the content is.
    mutating func show() {
        visible = true
        anchor = last
    }
}

extension ScrollGeometry {
    /// How far the content has scrolled from its top, for a [ScrollHider], up
    /// to its end: pulled past the end it only springs back, which isn't
    /// scrolling back.
    var offsetFromTop: CGFloat {
        let end = contentSize.height + contentInsets.top + contentInsets.bottom - containerSize.height
        return min(contentOffset.y + contentInsets.top, max(end, 0))
    }

    /// Where the content is, for a [ScrollHider].
    var hiderPosition: ScrollHider.Position {
        ScrollHider.Position(offset: offsetFromTop, top: contentInsets.top, bottom: contentInsets.bottom)
    }
}

/// Keeps [visible] as a [ScrollHider] says while the content scrolls. A page
/// retains its tab bar state while covered; only its own scrolling changes it.
struct HideOnScroll: ViewModifier {
    @Binding var visible: Bool
    var enabled = true
    /// Whether the content is a web view, which tells of its scrolling its own way.
    var web = false
    /// Whether [visible] is the tab bar's, which fades out before it hides; see
    /// [TabBarFade].
    var tabBar = false
    @Environment(\.isCurrentNavigationPage) private var active
    @State private var hider = ScrollHider()
    @State private var fadingOut = false
    /// Bumped by each fade out and by stopping one, so that only the latest
    /// one's end counts.
    @State private var fades = 0

    func body(content: Content) -> some View {
        Group {
            if web {
                content.webViewOnScrollGeometryChange(for: ScrollHider.Position.self, of: \.hiderPosition) {
                    scrolled($1)
                }
            } else {
                content.onScrollGeometryChange(for: ScrollHider.Position.self, of: \.hiderPosition) { scrolled($1) }
            }
        }
        .onAppear {
            if !tabBar {
                hider.show()
                visible = true
            }
        }
        .onDisappear {
            finishScrolling()
        }
        .onChange(of: active) { _, active in
            if !active { finishScrolling() }
        }
    }

    private func finishScrolling() {
        // Navigation can interrupt the fade before it commits the hidden
        // state. Save its intended result and ignore its late completion.
        if tabBar { visible = hider.visible }
        stopFading(restore: !tabBar)
        if !tabBar { visible = true }
    }

    private func scrolled(_ position: ScrollHider.Position) {
        guard active else { return }
        hider.scrolled(to: position)
        if !enabled {
            hider.show()
            stopFading()
            visible = true
            return
        }
        if hider.visible {
            if fadingOut {
                stopFading()
            } else if !visible {
                withAnimation(.snappy(duration: 0.3)) { visible = true }
            }
        } else if visible, !fadingOut {
            guard tabBar else {
                withAnimation(.snappy(duration: 0.3)) { visible = false }
                return
            }
            fadingOut = true
            fades += 1
            let fade = fades
            TabBarFade.out {
                guard fade == fades else { return }
                fadingOut = false
                withAnimation(.snappy(duration: 0.3)) { visible = false }
            }
        }
    }

    private func stopFading(restore: Bool = true) {
        guard fadingOut else { return }
        fadingOut = false
        fades += 1
        if restore { TabBarFade.back() }
    }
}

/// Fades the tab bar out before it hides, which SwiftUI can't do: hiding it,
/// the system drops its buttons at once and then fades the empty glass,
/// whereas showing it fades both in, from the bar's alpha as it is.
@MainActor
enum TabBarFade {
    static func out(then done: @escaping () -> Void) {
        guard let bar = tabs()?.tabBar else { return done() }
        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .curveEaseIn]) {
            bar.alpha = 0
        } completion: { _ in
            done()
        }
    }

    /// Brings it back from a fade if it is still up. Hidden, it stays faded, as
    /// showing it fades it in from there.
    static func back() {
        guard let tabs = tabs(), !tabs.isTabBarHidden, tabs.tabBar.alpha < 1 else { return }
        UIView.animate(withDuration: 0.2, delay: 0, options: .beginFromCurrentState) { tabs.tabBar.alpha = 1 }
    }

    /// Brings it back, after it has had time to show, should it have come back
    /// some way that left it faded: up but faded, it would still take taps.
    static func checkShown() {
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            back()
        }
    }

    /// The app's `TabView`, from UIKit.
    private static func tabs() -> UITabBarController? {
        var controllers = UIApplication.shared.connectedScenes.compactMap {
            ($0 as? UIWindowScene)?.keyWindow?.rootViewController
        }
        while let controller = controllers.popLast() {
            if let tabs = controller as? UITabBarController { return tabs }
            controllers += controller.children
        }
        return nil
    }
}

extension View {
    /// The page's bottom toolbar, which goes away as the content scrolls on
    /// and comes back as it scrolls back.
    func bottomBarHidesOnScroll(_ visible: Binding<Bool>, enabled: Bool = true) -> some View {
        modifier(HideOnScroll(visible: visible, enabled: enabled))
            .toolbarVisibility(visible.wrappedValue ? .visible : .hidden, for: .bottomBar)
    }

    /// The tab bar under the page, likewise. The system's own way, shrinking it
    /// to two buttons, brings it back only at the top or the end, and has no
    /// way to bring it back with an animation.
    func tabBarHidesOnScroll(web: Bool = false) -> some View { modifier(TabBarHidesOnScroll(web: web)) }

    /// Shows or hides the tab bar as [visible] says, for a page whose lists set
    /// it through `HideOnScroll(tabBar: true)`.
    func tabBarVisible(_ visible: Bool) -> some View {
        modifier(PageTabBarVisibility(visible: visible))
    }
}

/// A covered page releases its toolbar preference without changing its saved
/// scroll state, so that the next page can choose its own visibility.
private struct PageTabBarVisibility: ViewModifier {
    let visible: Bool
    @Environment(\.isCurrentNavigationPage) private var active

    func body(content: Content) -> some View {
        // `.visible` would override a detail's `.hidden` further up the stack.
        content.toolbarVisibility(active && !visible ? .hidden : .automatic, for: .tabBar)
            .onChange(of: active && visible) { _, shown in
                if shown { TabBarFade.checkShown() }
            }
    }
}

private struct TabBarHidesOnScroll: ViewModifier {
    let web: Bool
    @State private var visible = true

    func body(content: Content) -> some View {
        content.modifier(HideOnScroll(visible: $visible, web: web, tabBar: true))
            .tabBarVisible(visible)
    }
}
