import SwiftUI

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

/// Keeps [visible] as a [ScrollHider] says while the content scrolls.
struct HideOnScroll: ViewModifier {
    @Binding var visible: Bool
    @State private var hider = ScrollHider()

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
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
