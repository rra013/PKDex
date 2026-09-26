//
//  Theme.swift
//  PKDex
//
//  Styles shared across screens, so a type, a role or a card looks the
//  same wherever it appears: the type palette and badge, the role colors
//  for the two sides of a matchup, abilities and items, and the card
//  styles.
//
//  The fills are the type colors players know from the games and most
//  community tools, which keeps all eighteen distinct. The system colors
//  used before gave Grass and Bug, Ghost and Dragon, and Psychic and Fairy
//  the same hue. Text on a fill is black or white, whichever contrasts
//  more; every type clears WCAG AA (4.5:1), which `TypePaletteTests`
//  checks.
//

import SwiftUI

// MARK: - Type Palette

enum TypePalette {
    /// sRGB fill per type, keyed by lowercased type name.
    static let hexByType: [String: UInt32] = [
        "normal":   0xA8A77A,
        "fire":     0xEE8130,
        "water":    0x6390F0,
        "electric": 0xF7D02C,
        "grass":    0x7AC74C,
        "ice":      0x96D9D6,
        "fighting": 0xC22E28,
        "poison":   0xA33EA1,
        "ground":   0xE2BF65,
        "flying":   0xA98FF3,
        "psychic":  0xF95587,
        "bug":      0xA6B91A,
        "rock":     0xB6A136,
        "ghost":    0x735797,
        "dragon":   0x6F35FC,
        "dark":     0x705746,
        "steel":    0xB7B7CE,
        "fairy":    0xD685AD,
    ]

    /// For names outside the eighteen: Stellar, "???", a typo.
    static let fallbackHex: UInt32 = 0x9A9A9A

    /// Matches `type` case-insensitively, so "Fire" and "fire" agree.
    static func hex(for type: String) -> UInt32 {
        hexByType[type.lowercased()] ?? fallbackHex
    }

    static func fill(for type: String) -> Color {
        Color(hex: hex(for: type))
    }

    /// Black or white, whichever contrasts more with the type's fill.
    static func text(for type: String) -> Color {
        usesWhiteText(hex(for: type)) ? .white : .black
    }

    static func usesWhiteText(_ hex: UInt32) -> Bool {
        let fill = relativeLuminance(hex)
        return contrastRatio(1, fill) > contrastRatio(0, fill)
    }

    /// WCAG 2 relative luminance of an sRGB color: 0 for black, 1 for white.
    static func relativeLuminance(_ hex: UInt32) -> Double {
        func linear(_ shift: UInt32) -> Double {
            let c = Double((hex >> shift) & 0xFF) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0)
    }

    /// WCAG 2 contrast ratio between two relative luminances, 1 to 21.
    static func contrastRatio(_ a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

// MARK: - Role Colors

/// Colors with one meaning across the app.
///
/// Each role has a light- and a dark-mode value, chosen to clear WCAG AA
/// (4.5:1) as small text on the page, on grouped rows, and on a 15% tint
/// of itself (the chip style most screens use), and as a fill under
/// `textOnFill`. `ColorRoleTests` checks all of it. System colors miss
/// this in light mode: orange text on white is about 2:1.
enum ColorRole: String, CaseIterable {
    /// The two sides of a matchup: Pokémon 1 and Pokémon 2 in the calc.
    /// Teal and pink, because the calc already uses red (Champions,
    /// warnings, KOs) and blue (the default accent) for other things.
    case side1, side2
    case ability, item

    var color: Color { Color(light: light, dark: dark) }

    var light: UInt32 {
        switch self {
        case .side1:   return 0x00687A
        case .side2:   return 0xAC187C
        case .ability: return 0xA73800
        case .item:    return 0x186D2E
        }
    }

    var dark: UInt32 {
        switch self {
        case .side1:   return 0x40CBE0
        case .side2:   return 0xFF7FD0
        case .ability: return 0xFFB340
        case .item:    return 0x30DB5B
        }
    }

    /// Text on a solid fill of any role: white in light mode, black in dark.
    static let textOnFill = Color(light: 0xFFFFFF, dark: 0x000000)
}

// MARK: - Hex Colors

extension Color {
    /// An sRGB color from a 0xRRGGBB value.
    init(hex: UInt32) {
        let (red, green, blue) = rgb(hex)
        self.init(red: red, green: green, blue: blue)
    }

    /// A color with separate light- and dark-mode values.
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            let (red, green, blue) = rgb(traits.userInterfaceStyle == .dark ? dark : light)
            return UIColor(red: red, green: green, blue: blue, alpha: 1)
        })
        #else
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let (red, green, blue) = rgb(isDark ? dark : light)
            return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        })
        #endif
    }
}

private func rgb(_ hex: UInt32) -> (Double, Double, Double) {
    (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
}

// MARK: - Cards

/// Card geometry shared by every screen.
enum CardMetrics {
    static let cornerRadius: CGFloat = 14
    static let padding: CGFloat = 16
    static let insetCornerRadius: CGFloat = 10
    static let insetPadding: CGFloat = 12
}

extension View {
    /// A section of a page that sits on `cardPage()`: full width, content
    /// leading. Uses the grouped background colors, so a card is white on
    /// light gray in light mode and dark gray on black in dark mode. A
    /// `.background` card is black on black in dark mode, with nothing to
    /// show its edge.
    func card(padding: CGFloat = CardMetrics.padding) -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: CardMetrics.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    /// A box set into a card: light gray in light mode, a lighter gray than
    /// the card in dark mode.
    func insetCard(padding: CGFloat = CardMetrics.insetPadding) -> some View {
        self.padding(padding)
            .background(Color(.tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: CardMetrics.insetCornerRadius, style: .continuous))
    }

    /// The page behind cards.
    func cardPage() -> some View {
        background(Color(.systemGroupedBackground))
    }
}

/// A titled card: an icon and title, a divider, then the content.
struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    var iconColor: Color = .primary
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon).foregroundStyle(iconColor)
            }
            .font(.headline)
            Divider()
            content
        }
        .card()
    }
}

// MARK: - Type Badge

struct TypeBadge: View {
    let type: String
    var body: some View {
        Text(type)
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(TypePalette.text(for: type))
            .background(TypePalette.fill(for: type), in: Capsule())
    }
}
