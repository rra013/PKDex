//
//  ContentView.swift
//  PKDex
//
//  Created by Rishi Anand on 4/13/26.
//

import SwiftUI
import SwiftData
import WebKit

// MARK: - App Tab Definition

enum AppTab: String, CaseIterable, Identifiable {
    case monIndex, damageCalc, sets, teams, speedTiers, rngTools, settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .monIndex:   return "Mon Index"
        case .damageCalc: return "Damage Calc"
        case .sets:       return "Sets"
        case .teams:      return "Teams"
        case .speedTiers: return "Speed Tiers"
        case .rngTools:   return "RNG Tools"
        case .settings:   return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .monIndex:   return "list.bullet"
        case .damageCalc: return "bolt.fill"
        case .sets:       return "square.and.pencil"
        case .teams:      return "person.3"
        case .speedTiers: return "hare"
        case .rngTools:   return "dice"
        case .settings:   return "gear"
        }
    }

    static let allUserTabs: [AppTab] = [.monIndex, .damageCalc, .sets, .teams, .speedTiers, .rngTools]
    static let defaultEnabledRaw = allUserTabs.map(\.rawValue).joined(separator: ",")
}

// MARK: - Accent Color

enum AppAccentColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .red:    return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green:  return .green
        case .mint:   return .mint
        case .teal:   return .teal
        case .cyan:   return .cyan
        case .blue:   return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink:   return .pink
        }
    }
}

// MARK: - Appearance Mode

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

struct ContentView: View {
    @AppStorage("enabledTabs") private var enabledTabsRaw: String = AppTab.defaultEnabledRaw
    @AppStorage("defaultTab") private var defaultTabRaw: String = AppTab.monIndex.rawValue
    @AppStorage("appAccentColor") private var accentColorRaw: String = AppAccentColor.blue.rawValue
    @AppStorage("appAppearance") private var appearanceRaw: String = AppAppearance.system.rawValue

    @State private var selectedTab: AppTab?

    private var enabledTabs: [AppTab] {
        let raw = enabledTabsRaw.split(separator: ",").map(String.init)
        let tabs = raw.compactMap { AppTab(rawValue: $0) }
        return tabs.isEmpty ? AppTab.allUserTabs : tabs
    }

    private var visibleTabs: [AppTab] {
        enabledTabs + [.settings]
    }

    private var accentColor: Color {
        (AppAccentColor(rawValue: accentColorRaw) ?? .blue).color
    }

    private var appearance: ColorScheme? {
        (AppAppearance(rawValue: appearanceRaw) ?? .system).colorScheme
    }

    var body: some View {
        TabView(selection: Binding(
            get: { selectedTab ?? AppTab(rawValue: defaultTabRaw) ?? .monIndex },
            set: { selectedTab = $0 }
        )) {
            ForEach(visibleTabs) { tab in
                tabContent(for: tab)
                    .tabItem { Label(tab.label, systemImage: tab.icon) }
                    .tag(tab)
            }
        }
        .tint(accentColor)
        .preferredColorScheme(appearance)
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .monIndex:   PokedexTab()
        case .damageCalc: DamageCalculatorView()
        case .sets:       SetListView()
        case .teams:      TeamListView()
        case .speedTiers: SpeedTierView()
        case .rngTools:   RNGToolsView()
        case .settings:   SettingsView()
        }
    }
}

// MARK: - Pokédex Tab (extracted from original ContentView)

private struct PokedexTab: View {
    @Query(sort: \PKMN.nationalPokedexNumber) private var allPokemon: [PKMN]
    @AppStorage("defaultGeneration") private var defaultGeneration: String = PokedexFilter.champions.rawValue
    @State private var selectedFilter: PokedexFilter?
    @State private var searchText = ""

    private var activeFilter: PokedexFilter {
        selectedFilter ?? PokedexFilter(rawValue: defaultGeneration) ?? .champions
    }

    var body: some View {
        NavigationStack {
            Group {
                if allPokemon.isEmpty {
                    ContentUnavailableView {
                        Label("No Mons Found", systemImage: "antenna.radiowaves.left.and.right")
                    } description: {
                        Text("Syncing with PokeAPI... please wait.")
                    }
                } else {
                    FilteredList(filter: activeFilter, searchText: searchText)
                }
            }
            .navigationTitle("Mon Index")
            .searchable(text: $searchText, prompt: "Search Mons")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        ForEach(PokedexFilter.allCases) { filter in
                            Button(filter.title) { selectedFilter = filter }
                        }
                    } label: {
                        Label(activeFilter.title, systemImage: "line.3.horizontal.decrease.circle")
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
