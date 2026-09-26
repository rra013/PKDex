//
//  ColorRoleTests.swift
//  PKDexTests
//
//  Covers `ColorRole`: every role's light- and dark-mode values clear WCAG
//  AA (4.5:1) as text on the backgrounds the app draws them on, including
//  a 15% tint of the role itself (the chip style), and as a fill under
//  `textOnFill`. Also checks the roles stay distinct.
//

import Testing
@testable import PKDex

@Suite("Color Roles")
struct ColorRoleTests {

    /// System backgrounds and grouped-row colors in each mode.
    private static let lightBackgrounds: [UInt32] = [0xFFFFFF, 0xF2F2F7]
    private static let darkBackgrounds: [UInt32] = [0x000000, 0x1C1C1E, 0x2C2C2E]
    /// The strongest tint any screen puts behind role-colored text.
    private static let chipTint = 0.15

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        TypePalette.contrastRatio(TypePalette.relativeLuminance(a), TypePalette.relativeLuminance(b))
    }

    /// `color` at `alpha` over `background`, per channel, as the screen draws it.
    private func blend(_ color: UInt32, over background: UInt32, alpha: Double) -> UInt32 {
        [16, 8, 0].reduce(UInt32(0)) { result, shift in
            let top = Double((color >> UInt32(shift)) & 0xFF)
            let bottom = Double((background >> UInt32(shift)) & 0xFF)
            return result | UInt32((top * alpha + bottom * (1 - alpha)).rounded()) << UInt32(shift)
        }
    }

    @Test("Light-mode text clears 4.5:1 on the page, grouped rows and its own tint",
          arguments: ColorRole.allCases)
    func lightText(role: ColorRole) {
        for background in Self.lightBackgrounds {
            #expect(contrast(role.light, background) >= 4.5)
            let tint = blend(role.light, over: background, alpha: Self.chipTint)
            #expect(contrast(role.light, tint) >= 4.5, "\(role) on its tint")
        }
    }

    @Test("Dark-mode text clears 4.5:1 on the page, grouped rows and its own tint",
          arguments: ColorRole.allCases)
    func darkText(role: ColorRole) {
        for background in Self.darkBackgrounds {
            #expect(contrast(role.dark, background) >= 4.5)
            let tint = blend(role.dark, over: background, alpha: Self.chipTint)
            #expect(contrast(role.dark, tint) >= 4.5, "\(role) on its tint")
        }
    }

    @Test("Text on a solid fill clears 4.5:1 in both modes", arguments: ColorRole.allCases)
    func textOnFill(role: ColorRole) {
        #expect(contrast(0xFFFFFF, role.light) >= 4.5)
        #expect(contrast(0x000000, role.dark) >= 4.5)
    }

    @Test("Every role has its own color in each mode")
    func distinct() {
        #expect(Set(ColorRole.allCases.map(\.light)).count == ColorRole.allCases.count)
        #expect(Set(ColorRole.allCases.map(\.dark)).count == ColorRole.allCases.count)
    }
}
