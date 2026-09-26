//
//  FlowLayoutTests.swift
//  PKDexTests
//
//  Covers `FlowLayout.lines`, which decides where a row of chips wraps:
//  everything on one line when it fits, spacing counted between views only,
//  a new line when the next view doesn't fit, and an oversized view on a
//  line of its own.
//

import Testing
import CoreGraphics
@testable import PKDex

@Suite("Flow Layout")
struct FlowLayoutTests {

    private func lines(_ widths: [CGFloat], in maxWidth: CGFloat, spacing: CGFloat = 6) -> [[Int]] {
        FlowLayout.lines(widths: widths, maxWidth: maxWidth, spacing: spacing)
    }

    @Test("Views that fit share one line")
    func oneLine() {
        #expect(lines([40, 40, 40], in: 200) == [[0, 1, 2]])
    }

    @Test("Spacing counts between views, not after the last")
    func exactFit() {
        // 40 + 6 + 40 + 6 + 40 = 132 exactly.
        #expect(lines([40, 40, 40], in: 132) == [[0, 1, 2]])
        #expect(lines([40, 40, 40], in: 131) == [[0, 1], [2]])
    }

    @Test("Sub-point rounding doesn't wrap the last view")
    func roundingSlack() {
        // Placement can see a width a fraction of a point under the one
        // measured; that mustn't move a view to an unmeasured line.
        #expect(lines([40, 40, 40], in: 131.7) == [[0, 1, 2]])
        #expect(lines([40.1, 40.1, 40.1], in: 132) == [[0, 1, 2]])
    }

    @Test("A view that doesn't fit starts the next line")
    func wraps() {
        #expect(lines([60, 60, 60, 60], in: 130) == [[0, 1], [2, 3]])
    }

    @Test("A view wider than a line gets a line to itself")
    func oversized() {
        #expect(lines([30, 300, 30], in: 100) == [[0], [1], [2]])
        #expect(lines([300], in: 100) == [[0]])
    }

    @Test("No views, no lines; unlimited width, one line")
    func edgeCases() {
        #expect(lines([], in: 100).isEmpty)
        #expect(lines([500, 500, 500], in: .infinity) == [[0, 1, 2]])
    }
}
