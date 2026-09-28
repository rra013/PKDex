//
//  AbilityNameTests.swift
//  PKDexTests
//
//  Covers `formatAbilityName`, which turns PokeAPI's ability slugs into
//  official names, and the Serebii links the Ability Index builds from
//  those names. The slugs are from the stored data; the Serebii slugs
//  were checked against its ability pages.
//

import Testing
import Foundation
@testable import PKDex

@Suite("Ability Names")
struct AbilityNameTests {

    @Test("Slugs become official names",
          arguments: [
              ("air-lock", "Air Lock"),
              ("intimidate", "Intimidate"),
              ("beads-of-ruin", "Beads of Ruin"),
              ("power-of-alchemy", "Power of Alchemy"),
              ("zero-to-hero", "Zero to Hero"),
              ("minds-eye", "Mind's Eye"),
              ("soul-heart", "Soul-Heart"),
              ("well-baked-body", "Well-Baked Body"),
              ("rks-system", "RKS System"),
              ("as-one-glastrier", "As One (Glastrier)"),
              ("as-one-spectrier", "As One (Spectrier)"),
          ])
    func officialNames(slug: String, name: String) {
        #expect(formatAbilityName(slug) == name)
    }

    @Test("An already-formatted name comes back unchanged",
          arguments: ["Air Lock", "Beads of Ruin", "Zero to Hero", "Mind's Eye",
                      "Soul-Heart", "Well-Baked Body", "RKS System", "As One (Glastrier)"])
    func formattedNamesStay(name: String) {
        #expect(formatAbilityName(name) == name)
    }

    @Test("Serebii links use the name without spaces, keeping hyphens and apostrophes",
          arguments: [
              ("Mold Breaker", "moldbreaker"),
              ("Beads of Ruin", "beadsofruin"),
              ("Soul-Heart", "soul-heart"),
              ("Well-Baked Body", "well-bakedbody"),
              ("Mind's Eye", "mind'seye"),
              ("RKS System", "rkssystem"),
              ("As One (Glastrier)", "asone-unnervechillingneigh"),
              ("As One (Spectrier)", "asone-unnervegrimneigh"),
          ])
    func serebiiLinks(name: String, slug: String) {
        #expect(AbilityDetailView.serebiiURL(for: name)?.absoluteString
                == "https://www.serebii.net/abilitydex/\(slug).shtml")
    }
}
