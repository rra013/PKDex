//
//  ContentView.swift
//  PKDex
//
//  Created by Rishi Anand on 4/13/26.
//

import SwiftUI
import SwiftData
import WebKit

struct ContentView: View {
    @Query(sort: \PKMN.nationalPokedexNumber) private var allPokemon: [PKMN]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            PokedexTab()
                .tabItem { Label("Pokédex", systemImage: "list.bullet") }

            DamageCalculatorView()
                .tabItem { Label("Damage Calc", systemImage: "bolt.fill") }
        }
    }
}

// MARK: - Pokédex Tab (extracted from original ContentView)

private struct PokedexTab: View {
    @Query(sort: \PKMN.nationalPokedexNumber) private var allPokemon: [PKMN]
    @Environment(\.modelContext) private var modelContext
    @State private var selectedFilter: PokedexFilter = .champions
    @State private var searchText = ""

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
                    FilteredList(filter: selectedFilter, searchText: searchText)
                }
            }
            .navigationTitle("Pokédex")
            .searchable(text: $searchText, prompt: "Search Pokemon")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Reset") {
                        Button("Emergency Reset", role: .destructive) {
                            UserDefaults.standard.removeObject(forKey: "hasCompletedInitialSync")
                            UserDefaults.standard.removeObject(forKey: "hasCompletedCalcSync")
                            try? modelContext.delete(model: PKMN.self)
                            try? modelContext.delete(model: Gen8Pokemon.self)
                            try? modelContext.delete(model: Gen9Pokemon.self)
                            try? modelContext.delete(model: PKMNStats.self)
                            try? modelContext.delete(model: MoveData.self)
                            try? modelContext.save()
                            print("App reset! Restart the app to re-sync.")
                        }
                    }
                }

                ToolbarItem(placement: .automatic) {
                    Menu {
                        ForEach(PokedexFilter.allCases) { filter in
                            Button(filter.title) { selectedFilter = filter }
                        }
                    } label: {
                        Label(selectedFilter.title, systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }
}

// MARK: - Filter Enum

enum PokedexFilter: String, CaseIterable, Identifiable {
    case all, gen1, gen2, gen3, gen4, gen5, gen6, gen7, gen8, gen9, champions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:       return "All"
        case .gen1:      return "Gen I"
        case .gen2:      return "Gen II"
        case .gen3:      return "Gen III"
        case .gen4:      return "Gen IV"
        case .gen5:      return "Gen V"
        case .gen6:      return "Gen VI"
        case .gen7:      return "Gen VII"
        case .gen8:      return "Gen VIII"
        case .gen9:      return "Gen IX"
        case .champions: return "Champions"
        }
    }
}

// MARK: - Filtered List

struct FilteredList: View {
    @Query private var filteredPokemon: [PKMN]
    private let filter: PokedexFilter
    private let searchText: String

    init(filter: PokedexFilter, searchText: String) {
        self.filter = filter
        self.searchText = searchText
        let predicate: Predicate<PKMN> = {
            switch filter {
            case .all:       return #Predicate<PKMN> { _ in true }
            case .gen1:      return #Predicate<PKMN> { $0.genOneLink != nil }
            case .gen2:      return #Predicate<PKMN> { $0.genTwoLink != nil }
            case .gen3:      return #Predicate<PKMN> { $0.genThreeLink != nil }
            case .gen4:      return #Predicate<PKMN> { $0.genFourLink != nil }
            case .gen5:      return #Predicate<PKMN> { $0.genFiveLink != nil }
            case .gen6:      return #Predicate<PKMN> { $0.genSixLink != nil }
            case .gen7:      return #Predicate<PKMN> { $0.genSevenLink != nil }
            case .gen8:      return #Predicate<PKMN> { $0.genEightLink != nil }
            case .gen9:      return #Predicate<PKMN> { $0.genNineLink != nil }
            case .champions: return #Predicate<PKMN> { $0.champsLink != nil }
            }
        }()
        _filteredPokemon = Query(filter: predicate, sort: \.nationalPokedexNumber)
    }

    private var visiblePokemon: [PKMN] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return filteredPokemon }
        return filteredPokemon.filter {
            $0.name.localizedStandardContains(trimmed) ||
            String($0.nationalPokedexNumber).contains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(filter.title).font(.headline)
                Spacer()
                Text("\(visiblePokemon.count)").foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            List(visiblePokemon) { pokemon in
                if let detailURL = pokemon.detailURL(for: filter) {
                    NavigationLink {
                        PokemonDetailView(pokemon: pokemon, filter: filter, detailURL: detailURL)
                    } label: {
                        PokemonRow(pokemon: pokemon)
                    }
                } else {
                    PokemonRow(pokemon: pokemon)
                }
            }
        }
    }
}

// MARK: - Row & Detail Views

private struct PokemonRow: View {
    let pokemon: PKMN

    var body: some View {
        HStack {
            Text("#\(pokemon.nationalPokedexNumber)")
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            Text(pokemon.name)
        }
    }
}

private struct PokemonDetailView: View {
    let pokemon: PKMN
    let filter: PokedexFilter
    let detailURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(filter.title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Link(detailURL.absoluteString, destination: detailURL)
                .font(.footnote)
            PokemonWebView(url: detailURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .navigationTitle(pokemon.name)
        .padding()
    }
}

private struct PokemonWebView: ViewRepresentable {
    let url: URL

    func makeView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        #if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #endif
        return webView
    }

    func updateView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }
}

#if os(iOS)
private typealias ViewRepresentable = UIViewRepresentable
private extension PokemonWebView {
    func makeUIView(context: Context) -> WKWebView { makeView(context: context) }
    func updateUIView(_ webView: WKWebView, context: Context) { updateView(webView, context: context) }
}
#else
private typealias ViewRepresentable = NSViewRepresentable
private extension PokemonWebView {
    func makeNSView(context: Context) -> WKWebView { makeView(context: context) }
    func updateNSView(_ webView: WKWebView, context: Context) { updateView(webView, context: context) }
}
#endif

// MARK: - URL Helper

private extension PKMN {
    func detailURL(for filter: PokedexFilter) -> URL? {
        let link: String? = switch filter {
        case .all:       champsLink ?? genNineLink ?? genEightLink ?? genSevenLink ?? genSixLink ?? genFiveLink ?? genFourLink ?? genThreeLink ?? genTwoLink ?? genOneLink
        case .gen1:      genOneLink
        case .gen2:      genTwoLink
        case .gen3:      genThreeLink
        case .gen4:      genFourLink
        case .gen5:      genFiveLink
        case .gen6:      genSixLink
        case .gen7:      genSevenLink
        case .gen8:      genEightLink
        case .gen9:      genNineLink
        case .champions: champsLink
        }
        guard let link else { return nil }
        return URL(string: link)
    }
}
