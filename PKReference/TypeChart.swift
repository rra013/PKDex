//
//  TypeChart.swift
//  PKReference
//
//  Loads `type_chart.json`: the 18 types and how effective each is against
//  each other. `allTypes` and `typeEffectivenessChart` read from here, so
//  their callers don't know the chart is data.
//
//  Loading is strict: an effectiveness row or column naming a type that
//  isn't in `types` fails the file, and `TypeChartTests` checks the bundled
//  one loads and agrees with the Showdown port's chart.
//

import Foundation

nonisolated enum TypeChart {

    struct Chart: Equatable, Sendable {
        /// Every type, in the order menus list them.
        var types: [String]
        /// Attacking type → defending type → multiplier. Missing pairs are 1.
        var effectiveness: [String: [String: Double]]

        /// `attacking`'s multiplier against a Pokémon of the `defending`
        /// types, by type alone: abilities such as Levitate aren't counted.
        func multiplier(_ attacking: String, against defending: [String]) -> Double {
            defending.reduce(1) { $0 * (effectiveness[attacking]?[$1] ?? 1) }
        }
    }

    enum LoadError: Error, Equatable {
        case unknownType(String)
    }

    /// The bundled chart, loaded once. An empty chart (and a debug
    /// assertion) if the file can't be read; every matchup is then neutral.
    static let bundled: Chart = {
        do {
            guard let url = Bundle.main.url(forResource: "type_chart", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try decode(Data(contentsOf: url))
        } catch {
            print("[TypeChart] failed to read type_chart.json: \(error)")
            assertionFailure("type_chart.json didn't load: \(error)")
            return Chart(types: [], effectiveness: [:])
        }
    }()

    static func decode(_ data: Data) throws -> Chart {
        let file = try JSONDecoder().decode(TypeChartFile.self, from: data)
        let known = Set(file.types)
        for (attacking, row) in file.effectiveness {
            for type in [attacking] + Array(row.keys) where !known.contains(type) {
                throw LoadError.unknownType(type)
            }
        }
        return Chart(types: file.types, effectiveness: file.effectiveness)
    }
}

/// `type_chart.json` as written. `about` is for people and isn't read.
nonisolated private struct TypeChartFile: Decodable, Sendable {
    let types: [String]
    let effectiveness: [String: [String: Double]]
}
