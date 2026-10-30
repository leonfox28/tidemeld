import SwiftUI
import WebKit

/// Whether a page's bottom toolbar shows, as the content scrolls: they go as it
/// scrolls on (the finger going up) and come back as it scrolls back, once it
/// has moved [threshold] one way, so a nudge leaves them as they are; at the
/// top they always show. The Android app's bars do the same.
struct ScrollHider: Equatable {
    var threshold: CGFloat = 24
    private(set) var visible = true
    /// Where the content was when the buttons last changed, or the scroll last
    /// turned.
    private var anchor: CGFloat = 0
    private var last: CGFloat = 0

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
}

extension ScrollGeometry {
    /// How far the content has scrolled from its top, for a [ScrollHider], up
    /// to its end: pulled past the end it only springs back, and a bar going
    /// away there pulls it back too, and neither is scrolling back.
    var offsetFromTop: CGFloat {
        let end = contentSize.height + contentInsets.top + contentInsets.bottom - containerSize.height
        return min(contentOffset.y + contentInsets.top, max(end, 0))
    }
}

/// Keeps [visible] as a [ScrollHider] says while the content scrolls.
struct HideOnScroll: ViewModifier {
    @Binding var visible: Bool
    @State private var hider = ScrollHider()

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: CGFloat.self, of: \.offsetFromTop) { _, offset in
            hider.scrolled(to: offset)
            if visible != hider.visible {
                withAnimation(.snappy(duration: 0.3)) { visible = hider.visible }
            }
        }
    }
}

extension View {
    /// The page's bottom toolbar, which goes away as the content scrolls on
    /// and comes back as it scrolls back.
    func bottomBarHidesOnScroll(_ visible: Binding<Bool>) -> some View {
        modifier(HideOnScroll(visible: visible))
            .toolbarVisibility(visible.wrappedValue ? .visible : .hidden, for: .bottomBar)
    }
}

/// Expands the tab bar again as the content scrolls back, once the system has
/// minimized it for scrolling on; see `Router.expandTabBar`.
struct TabBarFollowsScroll: ViewModifier {
    /// Whether the content is a web view, which tells of its scrolling its own way.
    let web: Bool
    @Environment(AppGraph.self) private var graph
    @State private var hider = ScrollHider()

    func body(content: Content) -> some View {
        if web {
            content.webViewOnScrollGeometryChange(for: CGFloat.self, of: \.offsetFromTop) { scrolled(to: $1) }
        } else {
            content.onScrollGeometryChange(for: CGFloat.self, of: \.offsetFromTop) { scrolled(to: $1) }
        }
    }

    private func scrolled(to offset: CGFloat) {
        let shown = hider.visible
        hider.scrolled(to: offset)
        if hider.visible, !shown { graph.router.expandTabBar() }
    }
}

extension View {
    /// For the scrolling content of a page with the tab bar under it.
    func tabBarFollowsScroll(web: Bool = false) -> some View { modifier(TabBarFollowsScroll(web: web)) }
}
