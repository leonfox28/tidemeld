import SwiftUI
import WebKit

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

/// Keeps [visible] as a [ScrollHider] says while the content scrolls, and shows
/// the bars again as the page comes back into view (a tab chosen, a page
/// closed over it), as the Android app does on choosing a tab.
struct HideOnScroll: ViewModifier {
    @Binding var visible: Bool
    /// Whether the content is a web view, which tells of its scrolling its own way.
    var web = false
    @State private var hider = ScrollHider()

    func body(content: Content) -> some View {
        Group {
            if web {
                content.webViewOnScrollGeometryChange(for: ScrollHider.Position.self, of: \.hiderPosition) { scrolled($1) }
            } else {
                content.onScrollGeometryChange(for: ScrollHider.Position.self, of: \.hiderPosition) { scrolled($1) }
            }
        }
        .onAppear {
            hider.show()
            visible = true
        }
    }

    private func scrolled(_ position: ScrollHider.Position) {
        hider.scrolled(to: position)
        if visible != hider.visible {
            withAnimation(.snappy(duration: 0.3)) { visible = hider.visible }
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

    /// The tab bar under the page, likewise. The system's own way, shrinking it
    /// to two buttons, brings it back only at the top or the end, and has no
    /// way to bring it back with an animation.
    func tabBarHidesOnScroll(web: Bool = false) -> some View { modifier(TabBarHidesOnScroll(web: web)) }
}

private struct TabBarHidesOnScroll: ViewModifier {
    let web: Bool
    @State private var visible = true

    func body(content: Content) -> some View {
        content.modifier(HideOnScroll(visible: $visible, web: web))
            // Not `.visible`, which from a page further down the stack would
            // keep the bar up over a page above that hides it.
            .toolbarVisibility(visible ? .automatic : .hidden, for: .tabBar)
    }
}
