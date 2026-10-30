import SwiftUI

/// Whether floating buttons show, as the content scrolls: they go as it
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
            if visible != hider.visible { visible = hider.visible }
        }
    }
}

extension View {
    /// Round glass buttons at the bottom right, over the content, which go away
    /// as it scrolls on and come back as it scrolls back. The content gets room
    /// at its foot to scroll its last rows clear of them.
    func floatingActions<Buttons: View>(
        visible: Binding<Bool>, @ViewBuilder _ buttons: @escaping () -> Buttons
    ) -> some View {
        modifier(HideOnScroll(visible: visible))
            .contentMargins(.bottom, 72, for: .scrollContent)
            .overlay(alignment: .bottomTrailing) {
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) { buttons() }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 8)
                .offset(y: visible.wrappedValue ? 0 : 120)
                .opacity(visible.wrappedValue ? 1 : 0)
                .animation(.snappy(duration: 0.3), value: visible.wrappedValue)
            }
    }
}

/// One of the floating buttons: an icon in glass, with a count beside it when
/// there is one.
struct FloatingButton: View {
    let label: String
    let symbol: String
    var count: String? = nil
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                if let count { Text(count).monospacedDigit() }
            }
            .font(.title3)
            .foregroundStyle(tint ?? AppTheme.foreground)
            .frame(minWidth: 28, minHeight: 28)
            .padding(.horizontal, count == nil ? 0 : 4)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(count == nil ? .circle : .capsule)
        .controlSize(.large)
        .accessibilityLabel(count.map { "\(label) \($0)" } ?? label)
    }
}
