//
//  TypePaletteTests.swift
//  PKReferenceTests
//
//  Covers `TypePalette`: every type has its own color, lookups ignore case,
//  unknown names get the fallback, and badge text clears WCAG AA contrast
//  (4.5:1) in both badge styles: on every fill, and on every tint in light
//  and dark mode.
//

import Testing
@testable import PKReference

@Suite("Type Palette")
struct TypePaletteTests {

    /// The eighteen types, as the Move Index's type filter lists them.
    private let types = MoveTypeFilter.allCases.filter { $0 != .all }.map(\.rawValue)

    @Test("Every type has a color, and no two share one")
    func distinctFills() {
        #expect(types.count == 18)
        let hexes = types.map { TypePalette.hexByType[$0.lowercased()] }
        #expect(!hexes.contains(nil))
        #expect(Set(hexes.compactMap { $0 }).count == types.count)
        #expect(TypePalette.hexByType.count == types.count)
    }

    @Test("Lookups ignore case")
    func caseInsensitive() {
        #expect(TypePalette.hex(for: "Fire") == 0xEE8130)
        #expect(TypePalette.hex(for: "fire") == 0xEE8130)
        #expect(TypePalette.hex(for: "FIRE") == 0xEE8130)
    }

    @Test("Unknown names get the fallback color")
    func fallback() {
        #expect(TypePalette.hex(for: "Stellar") == TypePalette.fallbackHex)
        #expect(TypePalette.hex(for: "???") == TypePalette.fallbackHex)
        #expect(TypePalette.hex(for: "") == TypePalette.fallbackHex)
    }

    @Test("Luminance and contrast match WCAG's reference values")
    func wcagMath() {
        #expect(TypePalette.relativeLuminance(0x000000) == 0)
        #expect(abs(TypePalette.relativeLuminance(0xFFFFFF) - 1) < 1e-9)
        #expect(abs(TypePalette.contrastRatio(0, 1) - 21) < 1e-9)
        // #777777 on white is the textbook just-under-AA gray: 4.48:1.
        let gray = TypePalette.relativeLuminance(0x777777)
        #expect(abs(TypePalette.contrastRatio(gray, 1) - 4.48) < 0.01)
    }

    @Test("Text on every fill has at least 4.5:1 contrast",
          arguments: MoveTypeFilter.allCases.filter { $0 != .all }.map(\.rawValue) + ["Stellar"])
    func textContrast(type: String) {
        let hex = TypePalette.hex(for: type)
        let fill = TypePalette.relativeLuminance(hex)
        let text: Double = TypePalette.usesWhiteText(hex) ? 1 : 0
        #expect(TypePalette.contrastRatio(fill, text) >= 4.5, "\(type) text contrast")
    }

    /// `color` at `alpha` over `background`, per channel, as the screen draws it.
    private func blend(_ color: UInt32, over background: UInt32, alpha: Double) -> UInt32 {
        [16, 8, 0].reduce(UInt32(0)) { result, shift in
            let top = Double((color >> UInt32(shift)) & 0xFF)
            let bottom = Double((background >> UInt32(shift)) & 0xFF)
            return result | UInt32((top * alpha + bottom * (1 - alpha)).rounded()) << UInt32(shift)
        }
    }

    @Test("Tinted badges keep 4.5:1 text in light and dark mode",
          arguments: MoveTypeFilter.allCases.filter { $0 != .all }.map(\.rawValue))
    func tintedContrast(type: String) {
        let fill = TypePalette.hex(for: type)
        // Cards, grouped rows and inset boxes; black text in light mode,
        // white in dark.
        for background: UInt32 in [0xFFFFFF, 0xF2F2F7] {
            let tint = TypePalette.relativeLuminance(blend(fill, over: background, alpha: TypePalette.tintOpacity))
            #expect(TypePalette.contrastRatio(tint, 0) >= 4.5, "\(type) on light")
        }
        for background: UInt32 in [0x000000, 0x1C1C1E, 0x2C2C2E] {
            let tint = TypePalette.relativeLuminance(blend(fill, over: background, alpha: TypePalette.tintOpacity))
            #expect(TypePalette.contrastRatio(tint, 1) >= 4.5, "\(type) on dark")
        }
    }

    /// Each type's color, plus the midpoint of every pair: a gradient's
    /// midpoint can be darker than either end.
    private var washColors: [UInt32] {
        let fills = MoveTypeFilter.allCases.filter { $0 != .all }.map { TypePalette.hex(for: $0.rawValue) }
        var colors = fills
        for (i, a) in fills.enumerated() {
            for b in fills[(i + 1)...] { colors.append(blend(a, over: b, alpha: 0.5)) }
        }
        return colors
    }

    @Test("Text keeps 4.5:1 on type-colored pages and cards, light and dark")
    func washContrast() {
        let page = (light: TypePalette.pageWashOpacity(dark: false), dark: TypePalette.pageWashOpacity(dark: true))
        let card = (light: TypePalette.cardWashOpacity(dark: false), dark: TypePalette.cardWashOpacity(dark: true))
        // Page, card and inset box backgrounds in each mode.
        let light: [(UInt32, Double)] = [(0xF2F2F7, page.light), (0xFFFFFF, card.light), (0xF2F2F7, card.light)]
        let dark: [(UInt32, Double)] = [(0x000000, page.dark), (0x1C1C1E, card.dark), (0x2C2C2E, card.dark)]
        for color in washColors {
            for (background, alpha) in light {
                let wash = TypePalette.relativeLuminance(blend(color, over: background, alpha: alpha))
                #expect(TypePalette.contrastRatio(wash, 0) >= 4.5)
            }
            for (background, alpha) in dark {
                let wash = TypePalette.relativeLuminance(blend(color, over: background, alpha: alpha))
                #expect(TypePalette.contrastRatio(wash, 1) >= 4.5)
            }
        }
    }
}
