//
//  MoveIndexView.swift
//  PKDex
//

import SwiftUI
import SwiftData
import WebKit

// MARK: - Type Filter

enum MoveTypeFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case normal = "Normal"
    case fire = "Fire"
    case water = "Water"
    case electric = "Electric"
    case grass = "Grass"
    case ice = "Ice"
    case fighting = "Fighting"
    case poison = "Poison"
    case ground = "Ground"
    case flying = "Flying"
    case psychic = "Psychic"
    case bug = "Bug"
    case rock = "Rock"
    case ghost = "Ghost"
    case dragon = "Dragon"
    case dark = "Dark"
    case steel = "Steel"
    case fairy = "Fairy"

    var id: String { rawValue }
    var label: String { rawValue }
}

// MARK: - Move Index Tab

struct MoveIndexTab: View {
    @Query(sort: \MoveData.name) private var allMoves: [MoveData]
    @AppStorage("defaultGeneration") private var defaultGeneration: String = PokedexFilter.champions.rawValue
    @State private var selectedGenFilter: PokedexFilter?
    @State private var selectedTypeFilter: MoveTypeFilter = .all
    @State private var searchText = ""

    private var activeGenFilter: PokedexFilter {
        selectedGenFilter ?? PokedexFilter(rawValue: defaultGeneration) ?? .champions
    }

    private var filteredMoves: [MoveData] {
        allMoves.filter { move in
            let maxGen = activeGenFilter.maxMoveGenerationId
            if maxGen < Int.max && move.generationId > maxGen { return false }

            if selectedTypeFilter != .all && move.type != selectedTypeFilter.rawValue {
                return false
            }

            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !move.name.localizedStandardContains(trimmed) {
                return false
            }

            return true
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if allMoves.isEmpty {
                    ContentUnavailableView {
                        Label("No Moves Found", systemImage: "antenna.radiowaves.left.and.right")
                    } description: {
                        Text("Syncing with PokeAPI... please wait.")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(activeGenFilter.title)
                                .font(.headline)
                            if selectedTypeFilter != .all {
                                Text("· \(selectedTypeFilter.label)")
                                    .font(.headline)
                                    .foregroundStyle(typeColorMap[selectedTypeFilter.rawValue] ?? .gray)
                            }
                            Spacer()
                            Text("\(filteredMoves.count)")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                        List(filteredMoves) { move in
                            NavigationLink {
                                MoveDetailView(move: move, genFilter: activeGenFilter)
                            } label: {
                                MoveRow(move: move)
                            }
                        }
                        .scrollDismissesKeyboard(.interactively)
                    }
                }
            }
            .navigationTitle("Move Index")
            .searchable(text: $searchText, prompt: "Search Moves")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        ForEach(PokedexFilter.allCases) { filter in
                            Button(filter.title) { selectedGenFilter = filter }
                        }
                    } label: {
                        Label(activeGenFilter.title, systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Menu {
                        ForEach(MoveTypeFilter.allCases) { filter in
                            Button(filter.label) { selectedTypeFilter = filter }
                        }
                    } label: {
                        Label(selectedTypeFilter.label, systemImage: "flame")
                    }
                }
            }
        }
    }
}

// MARK: - Move Row

private struct MoveRow: View {
    let move: MoveData

    var body: some View {
        HStack(spacing: 8) {
            Text(move.name)
                .lineLimit(1)
            Spacer()
            Text(move.type)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(typeColorMap[move.type] ?? .gray)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            Text(move.damageClass.capitalized)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .center)
            Text(move.power.map { "\($0)" } ?? "—")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }
}

// MARK: - Move Detail View

private struct MoveDetailView: View {
    let move: MoveData
    let genFilter: PokedexFilter

    private var serebiiURL: URL? {
        let slug = move.name.lowercased().replacingOccurrences(of: " ", with: "")
        let path = genFilter.attackdexPath
        return URL(string: "https://www.serebii.net/\(path)/\(slug).shtml")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(genFilter.title)
                .font(.headline)
                .foregroundStyle(.secondary)
            if let url = serebiiURL {
                Link(url.absoluteString, destination: url)
                    .font(.footnote)
                MoveWebView(url: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .navigationTitle(move.name)
        .padding()
    }
}

// MARK: - Web View

private struct MoveWebView: MoveViewRepresentable {
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
private typealias MoveViewRepresentable = UIViewRepresentable
private extension MoveWebView {
    func makeUIView(context: Context) -> WKWebView { makeView(context: context) }
    func updateUIView(_ webView: WKWebView, context: Context) { updateView(webView, context: context) }
}
#else
private typealias MoveViewRepresentable = NSViewRepresentable
private extension MoveWebView {
    func makeNSView(context: Context) -> WKWebView { makeView(context: context) }
    func updateNSView(_ webView: WKWebView, context: Context) { updateView(webView, context: context) }
}
#endif

// MARK: - PokedexFilter Extensions for Moves

extension PokedexFilter {
    var maxMoveGenerationId: Int {
        switch self {
        case .all:       return Int.max
        case .gen1:      return 1
        case .gen2:      return 2
        case .gen3:      return 3
        case .gen4:      return 4
        case .gen5:      return 5
        case .gen6:      return 6
        case .gen7:      return 7
        case .gen8:      return 8
        case .gen9:      return 9
        case .champions: return 9
        }
    }

    var attackdexPath: String {
        switch self {
        case .gen1:      return "attackdex-rby"
        case .gen2:      return "attackdex-gs"
        case .gen3:      return "attackdex"
        case .gen4:      return "attackdex-dp"
        case .gen5:      return "attackdex-bw"
        case .gen6:      return "attackdex-xy"
        case .gen7:      return "attackdex-sm"
        case .gen8:      return "attackdex-swsh"
        case .gen9:      return "attackdex-sv"
        case .champions: return "attackdex-champions"
        case .all:       return "attackdex-sv"
        }
    }
}
