//
//  TeamSearchFixtures.swift
//  PKDexTests
//
//  Shared fixtures for the Team Search suites: a small regulation (real
//  species, form names, Mega Stones and Mega abilities, in the bundled
//  JSONs' shape), a trimmed copy of team_search_vocab.json, and helpers for
//  building tournament teams. Hermetic: nothing is read from the bundle.
//

import Foundation
@testable import PKDex

enum TeamSearchFixtures {

    static let regulationJSON = """
    {
      "species_whitelist": ["Incineroar", "Garchomp", "Gardevoir", "Charizard", "Arcanine",
        "Indeedee", "Tauros", "Floette", "Kommo-o", "Mr. Rime", "Rillaboom", "Pelipper",
        "Farigiraf", "Gengar", "Kingambit", "Whimsicott", "Sneasler", "Torkoal", "Sinistcha",
        "Dragonite"],
      "regional_forms_allowed": [
        {"base": "Arcanine", "form": "Hisui"},
        {"base": "Tauros", "form": "Paldea-Combat"},
        {"base": "Tauros", "form": "Paldea-Blaze"}
      ],
      "mega_stones": {
        "Charizard-X": "Charizardite X", "Charizard-Y": "Charizardite Y",
        "Gardevoir": "Gardevoirite", "Gengar": "Gengarite", "Floette": "Floettite"
      }
    }
    """

    static let learnsetsJSON = """
    {
      "species": {
        "Incineroar": {"moves": ["Fake Out", "Parting Shot", "Flare Blitz", "Knock Off", "Snarl", "Protect"]},
        "Garchomp": {"moves": ["Earthquake", "Dragon Claw", "Rock Slide", "Protect"]},
        "Gardevoir": {"moves": ["Trick Room", "Moonblast", "Psychic", "Protect"],
                      "megas": [{"name": "Mega Gardevoir", "abilities": ["Pixilate"]}]},
        "Charizard": {"moves": ["Heat Wave", "Air Slash", "Protect", "Tailwind"],
                      "megas": [{"name": "Mega Charizard X", "abilities": ["Tough Claws"]},
                                {"name": "Mega Charizard Y", "abilities": ["Drought"]}]},
        "Arcanine": {"moves": ["Extreme Speed", "Flare Blitz", "Will-O-Wisp"],
                     "alternate_forms": [{"name": "Hisuian Form", "moves": ["Rock Slide", "Head Smash"]}]},
        "Indeedee": {"moves": ["Follow Me", "Psychic", "Trick Room"],
                     "alternate_forms": [{"name": "Female Form"}]},
        "Tauros": {"moves": ["Close Combat", "Raging Bull"],
                   "alternate_forms": [{"name": "Paldean Form"}]},
        "Floette": {"moves": ["Moonblast", "Light of Ruin"],
                    "megas": [{"name": "Mega Floette", "abilities": ["Fairy Aura"]}]},
        "Kommo-o": {"moves": ["Clangorous Soul"]},
        "Mr. Rime": {"moves": ["Freeze-Dry"]},
        "Rillaboom": {"moves": ["Fake Out", "Grassy Glide", "Wood Hammer"]},
        "Pelipper": {"moves": ["Hurricane", "Weather Ball", "Tailwind"]},
        "Farigiraf": {"moves": ["Trick Room", "Hyper Voice"]},
        "Gengar": {"moves": ["Perish Song", "Shadow Ball", "Protect"],
                   "megas": [{"name": "Mega Gengar", "abilities": ["Shadow Tag"]}]},
        "Kingambit": {"moves": ["Kowtow Cleave", "Sucker Punch"]},
        "Whimsicott": {"moves": ["Tailwind", "Moonblast", "Encore"]},
        "Sneasler": {"moves": ["Dire Claw", "Close Combat", "Fake Out"]},
        "Torkoal": {"moves": ["Eruption", "Heat Wave"]},
        "Sinistcha": {"moves": ["Rage Powder", "Matcha Gotcha"]},
        "Dragonite": {"moves": ["Extreme Speed", "Scale Shot"]}
      }
    }
    """

    static let vocabularyJSON = """
    {
      "archetypes": [
        {"id": "trick-room", "label": "Trick Room", "keywords": ["trick room", "tr"],
         "signals": {"moves": ["Trick Room"]}},
        {"id": "tailwind", "label": "Tailwind", "keywords": ["tailwind", "tw"],
         "signals": {"moves": ["Tailwind"]}},
        {"id": "sun", "label": "Sun", "keywords": ["sun"],
         "signals": {"moves": ["Sunny Day"], "abilities": ["Drought"]}},
        {"id": "psychic-terrain", "label": "Psychic Terrain", "keywords": ["psychic terrain"],
         "signals": {"moves": ["Psychic Terrain"], "abilities": ["Psychic Surge"]}},
        {"id": "redirection", "label": "Redirection", "keywords": ["redirection"],
         "signals": {"moves": ["Follow Me", "Rage Powder"]}},
        {"id": "perish-trap", "label": "Perish Trap", "keywords": ["perish trap"],
         "signals": {"moves": ["Perish Song"]},
         "requires": {"abilities": ["Shadow Tag"], "moves": ["Mean Look"]}}
      ],
      "negations": ["no", "not", "without", "except"],
      "connectors": ["or", "nor"],
      "contrast_words": ["and", "but", "with"],
      "stop_words": ["a", "the", "and", "but", "with", "team", "build", "me", "for", "some"],
      "form_noise": ["form", "breed"],
      "species_nicknames": {"chomp": "Garchomp", "incin": "Incineroar", "zard": "Charizard",
                            "ghost": "Missingno"},
      "single_word_moves": ["Encore", "Eruption"]
    }
    """

    static let vocabulary: TeamSearchVocabulary = {
        do {
            return try TeamSearchVocabulary(regulation: Data(regulationJSON.utf8),
                                            learnsets: Data(learnsetsJSON.utf8),
                                            vocabulary: Data(vocabularyJSON.utf8))
        } catch {
            fatalError("Fixture vocabulary failed to load: \(error)")
        }
    }()

    static let parser = TeamQueryParser(vocabulary: vocabulary)

    static func archetype(_ id: String) -> TeamArchetype {
        vocabulary.archetypes.first { $0.archetype.id == id }!.archetype
    }

    // MARK: Smogon

    /// A trimmed Smogon chaos file, in the real one's shape. Teammate shares
    /// work out to: Incineroar → Garchomp 50%, Charizard-Mega-Y 30%;
    /// Garchomp → Incineroar 75%, Charizard-Mega-Y 70%; Charizard-Mega-Y →
    /// Garchomp 90%, Incineroar 75%.
    static let smogonChaosJSON = """
    {
      "info": {"metagame": "gen9championsvgc2026regmb", "cutoff": 1760, "number of battles": 1000},
      "data": {
        "Incineroar": {"usage": 0.40, "Raw count": 400,
                       "Abilities": {"intimidate": 80.0, "blaze": 20.0},
                       "Teammates": {"Garchomp": 50.0, "Charizard-Mega-Y": 30.0, "Gardevoir": 0.0}},
        "Garchomp": {"usage": 0.30, "Raw count": 300, "Abilities": {"roughskin": 60.0},
                     "Teammates": {"Incineroar": 45.0, "Charizard-Mega-Y": 42.0}},
        "Charizard-Mega-Y": {"usage": 0.20, "Raw count": 200, "Abilities": {"drought": 40.0},
                             "Teammates": {"Garchomp": 36.0, "Incineroar": 30.0}},
        "Unused": {"usage": 0, "Raw count": 0, "Abilities": {}, "Teammates": {}}
      }
    }
    """

    // MARK: Teams

    /// Noon UTC, 2026-09-24.
    static let now = Date(timeIntervalSince1970: 1_790_251_200)

    static func member(_ name: String, _ slug: String? = nil, item: String? = nil,
                       ability: String? = nil,
                       moves: [String] = ["Protect"]) -> LimitlessStanding.TeamMember {
        .init(name: name, limitlessID: slug ?? name.lowercased(), item: item, ability: ability,
              attacks: moves, nature: nil, tera: nil)
    }

    static func standing(_ player: String, placing: Int?,
                         _ members: [LimitlessStanding.TeamMember]) -> LimitlessStanding {
        LimitlessStanding(player: player, name: player, country: nil, placing: placing,
                          record: nil, deck: nil, decklist: members, drop: nil)
    }

    /// An event `daysAgo` days before `now`.
    static func event(_ id: String, daysAgo: Int = 0, players: Int = 64,
                      _ standings: [LimitlessStanding]) -> CorpusEvent {
        let date = now.addingTimeInterval(-Double(daysAgo) * 86_400)
        let formatter = ISO8601DateFormatter()
        return CorpusEvent(
            tournament: LimitlessTournament(id: id, name: "Event \(id)", game: "VGC", format: "M-C",
                                            date: formatter.string(from: date), players: players),
            standings: standings, fetchedAt: now)
    }

    static func index(_ events: [CorpusEvent]) -> TeamSearchIndex {
        TeamSearchIndex(corpus: TeamCorpus(format: "M-C", events: events, listFetchedAt: now,
                                           missingEvents: []),
                        vocabulary: vocabulary)
    }

    /// Six members from names, each with `Protect` unless given moves.
    static func six(_ names: [String]) -> [LimitlessStanding.TeamMember] {
        names.map { member($0) }
    }
}
