//
//  TypePaletteTests.swift
//  PKDexTests
//
//  Covers `TypePalette`: every type has its own color, lookups ignore case,
//  unknown names get the fallback, and the text on every fill clears WCAG
//  AA contrast (4.5:1).
//

import Testing
@testable import PKDex

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
}
