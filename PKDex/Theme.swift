//
//  Theme.swift
//  PKDex
//
//  Styles shared across screens, so a type, a role, a card or a button
//  looks the same wherever it appears: the type palette and badge, the
//  role colors for the two sides of a matchup, abilities and items, the
//  card styles, the primary action button, and the layout tools that keep
//  screens working at large Dynamic Type sizes.
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

// MARK: - Buttons

/// The main action on a screen, such as Generate, Search or Start Battle:
/// the system's prominent button at large size, filled with the tint,
/// with the label spanning the full width. For a red action such as Stop,
/// add `.tint(.red)`.
struct PrimaryActionButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label.frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}

extension PrimitiveButtonStyle where Self == PrimaryActionButtonStyle {
    static var primaryAction: PrimaryActionButtonStyle { PrimaryActionButtonStyle() }
}

// MARK: - Dynamic Type

extension View {
    /// `frame(width:alignment:)` for a column of text. The width grows with
    /// Dynamic Type by the same factor as `style`, the column's font, so a
    /// label that fits at the default size fits at every size.
    func scaledWidth(_ width: CGFloat, relativeTo style: Font.TextStyle = .body,
                     alignment: Alignment = .center) -> some View {
        modifier(ScaledWidth(width: width, style: style, alignment: alignment))
    }

    /// A deliberate point size that still scales with Dynamic Type, by the
    /// same factor as `style`.
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular,
                    design: Font.Design = .default,
                    relativeTo style: Font.TextStyle = .body) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design, style: style))
    }
}

private struct ScaledWidth: ViewModifier {
    @ScaledMetric private var width: CGFloat
    private let alignment: Alignment

    init(width: CGFloat, style: Font.TextStyle, alignment: Alignment) {
        _width = ScaledMetric(wrappedValue: width, relativeTo: style)
        self.alignment = alignment
    }

    func body(content: Content) -> some View {
        content.frame(width: width, alignment: alignment)
    }
}

private struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

/// A row that becomes a column at accessibility text sizes, where its
/// pieces no longer fit side by side.
struct AdaptiveStack<Content: View>: View {
    var horizontalAlignment: HorizontalAlignment = .leading
    var verticalAlignment: VerticalAlignment = .center
    var spacing: CGFloat? = nil
    @ViewBuilder var content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: horizontalAlignment, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: verticalAlignment, spacing: spacing))
        layout { content }
    }
}

/// Lays views out left to right, starting a new line when the next one
/// doesn't fit: for rows of chips that outgrow the width at large text
/// sizes. Each view gets at most a line's width, and views are centered
/// vertically within their line.
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    /// `lineSpacing` defaults to `spacing`.
    init(spacing: CGFloat = 6, lineSpacing: CGFloat? = nil) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing ?? spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let sizes = subviews.map { $0.sizeThatFits(Self.proposal(maxWidth: maxWidth)) }
        let lines = Self.lines(widths: sizes.map(\.width), maxWidth: maxWidth, spacing: spacing)
        var width: CGFloat = 0
        var height: CGFloat = 0
        for (number, line) in lines.enumerated() {
            var lineWidth: CGFloat = 0
            var lineHeight: CGFloat = 0
            for (position, index) in line.enumerated() {
                lineWidth += sizes[index].width + (position > 0 ? spacing : 0)
                lineHeight = max(lineHeight, sizes[index].height)
            }
            width = max(width, lineWidth)
            height += lineHeight + (number > 0 ? lineSpacing : 0)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Break lines against the width `sizeThatFits` measured with, not
        // `bounds`: bounds come back at the reported width, which rounding
        // can shave just enough to push the last view onto a line the
        // reported height doesn't include.
        let maxWidth = proposal.width ?? bounds.width
        let childProposal = Self.proposal(maxWidth: maxWidth)
        let sizes = subviews.map { $0.sizeThatFits(childProposal) }
        var y = bounds.minY
        for line in Self.lines(widths: sizes.map(\.width), maxWidth: maxWidth, spacing: spacing) {
            let lineHeight = line.map { sizes[$0].height }.max() ?? 0
            var x = bounds.minX
            for index in line {
                subviews[index].place(at: CGPoint(x: x, y: y + (lineHeight - sizes[index].height) / 2),
                                      proposal: childProposal)
                x += sizes[index].width + spacing
            }
            y += lineHeight + lineSpacing
        }
    }

    static let roundingSlack: CGFloat = 0.5

    /// Each view at its ideal width, but no wider than a line.
    private static func proposal(maxWidth: CGFloat) -> ProposedViewSize {
        ProposedViewSize(width: maxWidth.isFinite ? maxWidth : nil, height: nil)
    }

    /// Indices of the views on each line, filling lines in order. A view
    /// wider than `maxWidth` gets a line to itself. Overshooting by less
    /// than `roundingSlack` still fits, so sub-point rounding in the
    /// widths never wraps a view.
    static func lines(widths: [CGFloat], maxWidth: CGFloat, spacing: CGFloat) -> [[Int]] {
        var lines: [[Int]] = []
        var current: [Int] = []
        var used: CGFloat = 0
        for (index, width) in widths.enumerated() {
            let needed = current.isEmpty ? width : used + spacing + width
            if !current.isEmpty && needed > maxWidth + roundingSlack {
                lines.append(current)
                current = [index]
                used = width
            } else {
                current.append(index)
                used = needed
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }
}

// MARK: - Type Badge

struct TypeBadge: View {
    let type: String
    var body: some View {
        Text(type)
            .font(.caption2.bold())
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(TypePalette.text(for: type))
            .background(TypePalette.fill(for: type), in: Capsule())
    }
}
