//
//  Theme.swift
//  PKDex
//
//  Styles shared across screens, so a type looks the same wherever it
//  appears: the type palette and the type badge.
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
        let hex = hex(for: type)
        return Color(red: Double((hex >> 16) & 0xFF) / 255,
                     green: Double((hex >> 8) & 0xFF) / 255,
                     blue: Double(hex & 0xFF) / 255)
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
