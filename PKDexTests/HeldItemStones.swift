//
//  HeldItemStones.swift
//  PKDexTests
//
//  The Mega stones tests name. Stones aren't declared in the app (they come
//  from `mega_forms.json`), so tests look them up by name; a missing one
//  fails loudly here rather than as a confusing nil later.
//

@testable import PKDex

extension HeldItem {
    static let charizarditeX = stone("Charizardite X")
    static let charizarditeY = stone("Charizardite Y")
    static let gengarite = stone("Gengarite")
    static let delphoxite = stone("Delphoxite")

    private static func stone(_ name: String) -> HeldItem {
        guard let item = HeldItem(rawValue: name), item.isMegaStone else {
            preconditionFailure("\(name) isn't a Mega stone in mega_forms.json")
        }
        return item
    }
}
