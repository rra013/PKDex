//
//  ColorRoleTests.swift
//  PKDexTests
//
//  Covers `ColorRole` and every `MatchupColors` pair: each color's light-
//  and dark-mode values clear WCAG AA (4.5:1) as text on the backgrounds
//  the app draws them on, including a 15% tint of the color itself (the
//  chip style), and as a fill under `textOnFill`. Also checks that each
//  pair's sides are easy to tell apart from each other and from the
//  ability and item colors, and that Blue & Gold's sides stay apart with
//  red-green color blindness, which is what it's offered for.
//

import Testing
import Foundation
@testable import PKDex

@Suite("Color Roles")
struct ColorRoleTests {

    /// A color drawn under the role rules: a role, or one side of a matchup pair.
    struct Swatch: CustomTestStringConvertible {
        let name: String
        let light: UInt32
        let dark: UInt32
        var testDescription: String { name }
    }

    static let roleSwatches = ColorRole.allCases.map {
        Swatch(name: $0.rawValue, light: $0.light, dark: $0.dark)
    }

    static func sideSwatches(_ colors: MatchupColors) -> [Swatch] {
        MatchupSide.allCases.map {
            Swatch(name: "\(colors.label) side \($0.number)",
                   light: colors.light(for: $0), dark: colors.dark(for: $0))
        }
    }

    static let allSwatches = roleSwatches + MatchupColors.allCases.flatMap(sideSwatches)

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
          arguments: allSwatches)
    func lightText(swatch: Swatch) {
        for background in Self.lightBackgrounds {
            #expect(contrast(swatch.light, background) >= 4.5)
            let tint = blend(swatch.light, over: background, alpha: Self.chipTint)
            #expect(contrast(swatch.light, tint) >= 4.5, "\(swatch.name) on its tint")
        }
    }

    @Test("Dark-mode text clears 4.5:1 on the page, grouped rows and its own tint",
          arguments: allSwatches)
    func darkText(swatch: Swatch) {
        for background in Self.darkBackgrounds {
            #expect(contrast(swatch.dark, background) >= 4.5)
            let tint = blend(swatch.dark, over: background, alpha: Self.chipTint)
            #expect(contrast(swatch.dark, tint) >= 4.5, "\(swatch.name) on its tint")
        }
    }

    @Test("Text on a solid fill clears 4.5:1 in both modes", arguments: allSwatches)
    func textOnFill(swatch: Swatch) {
        #expect(contrast(0xFFFFFF, swatch.light) >= 4.5)
        #expect(contrast(0x000000, swatch.dark) >= 4.5)
    }

    // MARK: Telling colors apart

    /// Distance in OKLab, scaled by 100. About 2 is barely noticeable;
    /// ability and item sit about 23 apart.
    private static func distance(_ a: UInt32, _ b: UInt32,
                                 vision: [[Double]] = identity) -> Double {
        func oklab(_ hex: UInt32) -> [Double] {
            let linear = [16, 8, 0].map { shift -> Double in
                let c = Double((hex >> UInt32(shift)) & 0xFF) / 255
                return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            let seen = vision.map { row in
                min(1, max(0, zip(row, linear).map(*).reduce(0, +)))
            }
            let (r, g, b) = (seen[0], seen[1], seen[2])
            let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
            let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
            let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
            return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s]
        }
        let (p, q) = (oklab(a), oklab(b))
        return 100 * sqrt(zip(p, q).map { ($0 - $1) * ($0 - $1) }.reduce(0, +))
    }

    private static let identity: [[Double]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
    /// Full deuteranopia and protanopia, from Machado, Oliveira and
    /// Fernandes (2009), applied to linear sRGB.
    private static let deuteranopia: [[Double]] = [[0.367322, 0.860646, -0.227968],
                                                   [0.280085, 0.672501, 0.047413],
                                                   [-0.011820, 0.042940, 0.968881]]
    private static let protanopia: [[Double]] = [[0.152286, 1.052583, -0.204868],
                                                 [0.114503, 0.786281, 0.099216],
                                                 [-0.003882, -0.048116, 1.051998]]

    @Test("Every pair's sides are far apart, and clear of the ability and item colors",
          arguments: MatchupColors.allCases)
    func distinctSides(colors: MatchupColors) {
        let sides = Self.sideSwatches(colors)
        #expect(Self.distance(sides[0].light, sides[1].light) >= 20)
        #expect(Self.distance(sides[0].dark, sides[1].dark) >= 20)
        for side in sides {
            for role in Self.roleSwatches {
                #expect(Self.distance(side.light, role.light) >= 8,
                        "\(side.name) against \(role.name), light")
                #expect(Self.distance(side.dark, role.dark) >= 8,
                        "\(side.name) against \(role.name), dark")
            }
        }
    }

    @Test("Blue & Gold's sides stay apart with red-green color blindness")
    func blueGoldForColorBlindness() {
        let sides = Self.sideSwatches(.blueGold)
        for vision in [Self.deuteranopia, Self.protanopia] {
            #expect(Self.distance(sides[0].light, sides[1].light, vision: vision) >= 20)
            #expect(Self.distance(sides[0].dark, sides[1].dark, vision: vision) >= 20)
        }
    }

    @Test("Ability and item have their own colors in each mode")
    func distinctRoles() {
        #expect(Set(ColorRole.allCases.map(\.light)).count == ColorRole.allCases.count)
        #expect(Set(ColorRole.allCases.map(\.dark)).count == ColorRole.allCases.count)
    }
}
