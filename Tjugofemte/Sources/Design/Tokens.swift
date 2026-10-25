import SwiftUI
import UIKit

/// The palette and type, in one place; nothing in a screen writes a literal color.
/// Each color has a light and a dark value and follows the system setting. Paper and ink with a
/// green cast, one green accent for the number that matters.
enum Tokens {
    /// The page behind everything.
    static let bg = Color(light: 0xf5f4ef, dark: 0x111413)
    /// A card's fill. Its border is `cardBorder`.
    static let card = Color(light: 0xffffff, dark: 0x1a1f1c)
    static let cardBorder = Color(light: 0x000000, dark: 0xffffff).opacity(0.06)
    /// The one accent: the savings number, the big button, the selected tab, income.
    static let accent = Color(light: 0x1f7a5c, dark: 0x9fd6b2)
    /// What sits on top of `accent`.
    static let onAccent = Color(light: 0xffffff, dark: 0x0f1412)
    /// Body text.
    static let text = Color(light: 0x171a18, dark: 0xedf0ec)
    /// A card's body line: quieter than `text`, louder than `muted`.
    static let body = Color(light: 0x3a403c, dark: 0xd3d9d4)
    /// Section labels and secondary text.
    static let muted = Color(light: 0x5d645f, dark: 0xa4aca6)
    /// The quietest text: captions under a row.
    static let dim = Color(light: 0x6b726d, dark: 0x8e968f)
    /// An unfilled field, chip or bar track.
    static let pill = Color(light: 0xecebe5, dark: 0x252b27)
    /// Over budget, expired access, errors. Brick rather than system red.
    static let over = Color(light: 0xb9483a, dark: 0xe9967f)
    /// An accent-tinted ground for a banner that needs attention without alarm.
    static let ground = Color(light: 0xe1efe7, dark: 0x24332b)
    static let separator = Color(light: 0x000000, dark: 0xffffff).opacity(0.06)
    /// The 50/30/20 groups: needs, wants, savings. On bars and dots only, never on a label or a number, and always
    /// next to a legend, so the split reads without telling the colors apart.
    static let groupNeed = Color(light: 0x3b74c4, dark: 0x5b8fd4)
    static let groupWant = Color(light: 0xc0661f, dark: 0xc97c3c)
    static let groupSaving = Color(light: 0x2a8f62, dark: 0x3fa577)

    static let cardRadius: CGFloat = 16
    static let fieldRadius: CGFloat = 10
    static let minimumTapTarget: CGFloat = 44
    static let screenPadding: CGFloat = 20

    /// Amounts and anything the eye compares down a column: rounded, monospaced digits.
    static func numberFont(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

extension Color {
    /// One value in light mode, another in dark, resolved by the system as the setting changes.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

/// Fixed-size type that still follows the user's text size setting.
private struct AppFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let rounded: Bool

    init(size: CGFloat, weight: Font.Weight, rounded: Bool) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.weight = weight
        self.rounded = rounded
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: rounded ? .rounded : .default).monospacedDigit())
    }
}

extension View {
    func appFont(size: CGFloat, weight: Font.Weight = .regular, rounded: Bool = false) -> some View {
        modifier(AppFont(size: size, weight: weight, rounded: rounded))
    }
}
