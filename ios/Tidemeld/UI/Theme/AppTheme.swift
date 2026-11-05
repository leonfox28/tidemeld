import SwiftUI
import UIKit

/// The palette of voytty's iOS app: rice white / dusty rose, dark first.
/// Controls stay native (and glass); these colour what is ours.
enum AppTheme {
    // Filled actions use dusty rose; links and small controls keep the warmer accent.
    static let primary = color(0xC69891, 0x9F6561)
    static let onPrimary = color(0x301D1D, 0xFFFFFF)
    static let accent = color(0xDC9B7F, 0x944630)
    static let primaryContainer = color(0x433026, 0xF2E2D8)
    static let onPrimaryContainer = color(0xF2E9DE, 0x30271F)
    static let background = color(0x191613, 0xF5F0E8)
    static let surface = color(0x25201B, 0xFFFCF7)
    static let elevated = color(0x312A23, 0xEAE1D6)
    static let foreground = color(0xF2E9DE, 0x30271F)
    static let secondary = color(0xB8A895, 0x776859)
    static let outline = color(0x41372D, 0xDDD1C4)
    static let success = color(0xA4BF98, 0x486B45)
    static let info = color(0x8BB7E8, 0x3466A2)
    static let warning = color(0xF0B85A, 0xB7791F)
    static let error = color(0xFF8F84, 0xBA1A1A)
    static let errorContainer = color(0x4A1A15, 0xFFDAD6)

    static let uiBackground = uiColor(0x191613, 0xF5F0E8)

    private static func color(_ dark: UInt32, _ light: UInt32) -> Color {
        Color(uiColor: uiColor(dark, light))
    }

    private static func uiColor(_ dark: UInt32, _ light: UInt32) -> UIColor {
        UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(rgb: hex)
        }
    }
}

extension UIColor {
    convenience init(rgb hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }
}

extension Color {
    init(rgb hex: UInt32) { self.init(uiColor: UIColor(rgb: hex)) }
}

/// For lists and forms: our background behind them, rows on [AppTheme.surface].
struct AppListStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.scrollContentBackground(.hidden)
            .background(AppTheme.background)
    }
}

extension View {
    func appListStyle() -> some View { modifier(AppListStyle()) }

    /// A page's background, under the bars too; the bars themselves stay glass.
    func appBackground() -> some View {
        background(AppTheme.background.ignoresSafeArea())
    }
}
