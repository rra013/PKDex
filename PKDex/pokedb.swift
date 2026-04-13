//
//  pokedb.swift
//  PKDex
//
//  Created by Rishi Anand on 4/13/26.
//

import Foundation
import SwiftData

@Model
final class PKMN {
    @Attribute(.unique) var nationalPokedexNumber: Int // Prevents duplicates in the DB
    var name: String
    var genOneLink: String?
    var genTwoLink: String?
    var genThreeLink: String?
    var genFourLink: String?
    var genFiveLink: String?
    var genSixLink: String?
    var genSevenLink: String?
    var genEightLink: String?
    var genNineLink: String?
    var champsLink: String?
    
    // By adding "= nil" to the end of the link parameters, they become optional to provide
    init(
        name: String,
        nationalPokedexNumber: Int,
        genOneLink: String? = nil,
        genTwoLink: String? = nil,
        genThreeLink: String? = nil,
        genFourLink: String? = nil,
        genFiveLink: String? = nil,
        genSixLink: String? = nil,
        genSevenLink: String? = nil,
        genEightLink: String? = nil,
        genNineLink: String? = nil,
        champsLink: String? = nil
    ) {
        self.name = name
        self.nationalPokedexNumber = nationalPokedexNumber
        self.genOneLink = genOneLink
        self.genTwoLink = genTwoLink
        self.genThreeLink = genThreeLink
        self.genFourLink = genFourLink
        self.genFiveLink = genFiveLink
        self.genSixLink = genSixLink
        self.genSevenLink = genSevenLink
        self.genEightLink = genEightLink
        self.genNineLink = genNineLink
        self.champsLink = champsLink
    }
}
