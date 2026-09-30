//
//  AbilityIndexView.swift
//  PKReference
//

import SwiftUI
import SwiftData
import WebKit

// MARK: - Ability Index Tab

struct AbilityIndexTab: View {
    @Query(sort: \PKMNStats.name) private var allPokemon: [PKMNStats]
    @State private var searchText = ""

    /// Every ability's official name ("Air Lock", not the stored
    /// "air-lock"), once each, in alphabetical order.
    private var allAbilities: [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for pkmn in allPokemon {
            for ability in pkmn.allAbilities {
                let trimmed = ability.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let name = formatAbilityName(trimmed)
                if seen.insert(name).inserted {
                    result.append(name)
                }
            }
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var filteredAbilities: [String] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allAbilities }
        return allAbilities.filter { $0.localizedStandardContains(trimmed) }
    }

    var body: some View {
        TabNavigationStack {
            Group {
                if allPokemon.isEmpty {
                    ContentUnavailableView {
                        Label("No Abilities Found", systemImage: "antenna.radiowaves.left.and.right")
                    } description: {
                        Text("Syncing with PokeAPI... please wait.")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Abilities").font(.headline)
                            Spacer()
                            Text("\(filteredAbilities.count)")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                        List(filteredAbilities, id: \.self) { ability in
                            NavigationLink {
                                AbilityDetailView(ability: ability)
                            } label: {
                                Text(ability).lineLimit(1)
                            }
                        }
                        .scrollDismissesKeyboard(.interactively)
                    }
                }
            }
            .navigationTitle("Ability Index")
            .searchable(text: $searchText, prompt: "Search Abilities")
            // An in-app search from Siri or Spotlight that names an ability.
            .onChange(of: AppNavigator.shared.request, initial: true) {
                guard case .indexSearch(.abilityIndex, let term) = AppNavigator.shared.request else { return }
                AppNavigator.shared.request = nil
                searchText = term
            }
        }
    }
}

// MARK: - Ability Detail View

struct AbilityDetailView: View {
    /// The ability's official name, from `formatAbilityName`.
    let ability: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let url = Self.serebiiURL(for: ability) {
                Link(url.absoluteString, destination: url)
                    .font(.footnote)
                AbilityWebView(url: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .navigationTitle(ability)
        .padding()
    }

    /// Serebii's page for an ability. Its slug is the official name in
    /// lowercase without spaces, keeping hyphens and apostrophes:
    /// "Mold Breaker" is "moldbreaker", "Soul-Heart" "soul-heart", and
    /// "Mind's Eye" "mind'seye".
    nonisolated static func serebiiURL(for ability: String) -> URL? {
        let slug = serebiiSlugExceptions[ability]
            ?? ability.lowercased().filter { $0 != " " && $0 != "." }
        return URL(string: "https://www.serebii.net/abilitydex/\(slug).shtml")
    }

    /// Serebii names As One's two forms after the abilities they combine.
    nonisolated private static let serebiiSlugExceptions = [
        "As One (Glastrier)": "asone-unnervechillingneigh",
        "As One (Spectrier)": "asone-unnervegrimneigh",
    ]
}

// MARK: - Web View

private struct AbilityWebView: AbilityViewRepresentable {
    let url: URL

    func makeView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
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
private typealias AbilityViewRepresentable = UIViewRepresentable
private extension AbilityWebView {
    func makeUIView(context: Context) -> WKWebView { makeView(context: context) }
    func updateUIView(_ webView: WKWebView, context: Context) { updateView(webView, context: context) }
}
#else
private typealias AbilityViewRepresentable = NSViewRepresentable
private extension AbilityWebView {
    func makeNSView(context: Context) -> WKWebView { makeView(context: context) }
    func updateNSView(_ webView: WKWebView, context: Context) { updateView(webView, context: context) }
}
#endif
