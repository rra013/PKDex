//
//  ContentView.swift
//  PKDex
//
//  Created by Rishi Anand on 4/13/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Query(sort: \PKMN.nationalPokedexNumber) private var allPokemon: [PKMN]
    @Environment(\.modelContext) private var modelContext
    @State private var selectedFilter: PokedexFilter = .all

    var body: some View {
        NavigationStack {
            Group {
                if allPokemon.isEmpty {
                    ContentUnavailableView {
                        Label("No Pokemon Found", systemImage: "antenna.radiowaves.left.and.right")
                    } description: {
                        Text("Syncing with PokeAPI... please wait.")
                    }
                } else {
                    FilteredList(filter: selectedFilter)
                }
            }
            .navigationTitle("Pokedex")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Reset") {
                        Button("Emergency Reset", role: .destructive) {
                            UserDefaults.standard.removeObject(forKey: "hasCompletedInitialSync")
                            try? modelContext.delete(model: PKMN.self)
                            try? modelContext.delete(model: Gen8Pokemon.self)
                            try? modelContext.delete(model: Gen9Pokemon.self)
                            try? modelContext.save()

                            print("App reset! Restart the app to re-sync.")
                        }
                    }
                }

                ToolbarItem(placement: .automatic) {
                    Menu {
                        ForEach(PokedexFilter.allCases) { filter in
                            Button(filter.title) {
                                selectedFilter = filter
                            }
                        }
                    } label: {
                        Label(selectedFilter.title, systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }
}

// 2. Helper Enum for Filters
enum PokedexFilter: String, CaseIterable, Identifiable {
    case all
    case gen1
    case gen2
    case gen3
    case gen4
    case gen5
    case gen6
    case gen7
    case gen8
    case gen9
    case champions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .gen1:
            return "Gen I"
        case .gen2:
            return "Gen II"
        case .gen3:
            return "Gen III"
        case .gen4:
            return "Gen IV"
        case .gen5:
            return "Gen V"
        case .gen6:
            return "Gen VI"
        case .gen7:
            return "Gen VII"
        case .gen8:
            return "Gen VIII"
        case .gen9:
            return "Gen IX"
        case .champions:
            return "Champions"
        }
    }
}

// 3. Sub-view to handle the Dynamic Query
struct FilteredList: View {
    @Query private var filteredPokemon: [PKMN]

    init(filter: PokedexFilter) {
        let predicate: Predicate<PKMN> = {
            switch filter {
            case .all:
                return #Predicate<PKMN> { _ in true }
            case .gen1:
                return #Predicate<PKMN> { $0.genOneLink != nil }
            case .gen2:
                return #Predicate<PKMN> { $0.genTwoLink != nil }
            case .gen3:
                return #Predicate<PKMN> { $0.genThreeLink != nil }
            case .gen4:
                return #Predicate<PKMN> { $0.genFourLink != nil }
            case .gen5:
                return #Predicate<PKMN> { $0.genFiveLink != nil }
            case .gen6:
                return #Predicate<PKMN> { $0.genSixLink != nil }
            case .gen7:
                return #Predicate<PKMN> { $0.genSevenLink != nil }
            case .gen8:
                return #Predicate<PKMN> { $0.genEightLink != nil }
            case .gen9:
                return #Predicate<PKMN> { $0.genNineLink != nil }
            case .champions:
                return #Predicate<PKMN> { $0.champsLink != nil }
            }
        }()
        
        _filteredPokemon = Query(filter: predicate, sort: \.nationalPokedexNumber)
    }

    var body: some View {
        List(filteredPokemon) { pokemon in
            HStack {
                Text("#\(pokemon.nationalPokedexNumber)")
                    .foregroundStyle(.secondary)
                    .frame(width: 40)
                Text(pokemon.name)
            }
        }
    }
}
