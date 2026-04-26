import SwiftUI

struct EncounterBrowserView: View {
    @State private var generation: EncBrowserGen = .gen3
    @State private var selectedGame: PFGame = .emerald
    @State private var selectedEncounter: PFEncounter = .grass
    @State private var areas: [PFEncounterAreaSwift] = []
    @State private var expandedArea: UUID?

    // Gen 4 settings
    @State private var tid: UInt16 = 0
    @State private var sid: UInt16 = 0

    enum EncBrowserGen: String, CaseIterable, Identifiable {
        case gen3 = "Gen 3"
        case gen4 = "Gen 4"
        var id: String { rawValue }
    }

    private var availableGames: [PFGame] {
        switch generation {
        case .gen3: return [.ruby, .sapphire, .emerald, .fireRed, .leafGreen]
        case .gen4: return [.diamond, .pearl, .platinum, .heartGold, .soulSilver]
        }
    }

    private var availableEncounters: [PFEncounter] {
        switch generation {
        case .gen3: return [.grass, .surfing, .oldRod, .goodRod, .superRod, .rockSmash]
        case .gen4: return [.grass, .surfing, .oldRod, .goodRod, .superRod, .rockSmash, .headbutt]
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Generation", selection: $generation) {
                    ForEach(EncBrowserGen.allCases) { g in Text(g.rawValue).tag(g) }
                }
                .pickerStyle(.segmented)
                .onChange(of: generation) {
                    let games = availableGames
                    if !games.contains(selectedGame) { selectedGame = games[0] }
                    let encounters = availableEncounters
                    if !encounters.contains(selectedEncounter) { selectedEncounter = encounters[0] }
                    loadEncounters()
                }

                HStack {
                    Picker("Game", selection: $selectedGame) {
                        ForEach(availableGames, id: \.rawValue) { g in
                            Text(gameName(g)).tag(g)
                        }
                    }
                    Picker("Type", selection: $selectedEncounter) {
                        ForEach(availableEncounters, id: \.rawValue) { e in
                            Text(e.displayName).tag(e)
                        }
                    }
                }
                .onChange(of: selectedGame) { loadEncounters() }
                .onChange(of: selectedEncounter) { loadEncounters() }

                if areas.isEmpty {
                    ContentUnavailableView("No Encounters",
                                           systemImage: "map",
                                           description: Text("Select a game and encounter type above."))
                } else {
                    Text("\(areas.count) locations found")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVStack(spacing: 8) {
                        ForEach(areas) { area in
                            EncounterAreaCard(area: area,
                                              isExpanded: expandedArea == area.id) {
                                withAnimation(.snappy) {
                                    expandedArea = expandedArea == area.id ? nil : area.id
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .onAppear { loadEncounters() }
    }

    private func loadEncounters() {
        switch generation {
        case .gen3:
            areas = PFBridge.getEncounters3(encounter: selectedEncounter, game: selectedGame)
        case .gen4:
            areas = PFBridge.getEncounters4(encounter: selectedEncounter, game: selectedGame,
                                             tid: tid, sid: sid)
        }
    }

    private func gameName(_ game: PFGame) -> String {
        switch game {
        case .ruby: return "Ruby"
        case .sapphire: return "Sapphire"
        case .emerald: return "Emerald"
        case .fireRed: return "FireRed"
        case .leafGreen: return "LeafGreen"
        case .diamond: return "Diamond"
        case .pearl: return "Pearl"
        case .platinum: return "Platinum"
        case .heartGold: return "HeartGold"
        case .soulSilver: return "SoulSilver"
        default: return "Unknown"
        }
    }
}

struct EncounterAreaCard: View {
    let area: PFEncounterAreaSwift
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(area.locationName.isEmpty ? "Location \(area.location)" : area.locationName)
                            .font(.headline)
                        Text("\(area.encounter.displayName) · Rate: \(area.rate)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if isExpanded {
                Divider()
                VStack(spacing: 0) {
                    ForEach(Array(area.slots.enumerated()), id: \.element.id) { index, slot in
                        HStack {
                            Text("#\(index)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .frame(width: 24, alignment: .trailing)
                            Text(slot.specieName)
                                .font(.body)
                            Spacer()
                            if slot.minLevel == slot.maxLevel {
                                Text("Lv. \(slot.minLevel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Lv. \(slot.minLevel)-\(slot.maxLevel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        if index < area.slots.count - 1 {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct StaticEncounterBrowserView: View {
    @State private var generation: StaticBrowserGen = .gen3
    @State private var category: Int32 = 5

    enum StaticBrowserGen: String, CaseIterable, Identifiable {
        case gen3 = "Gen 3"
        case gen4 = "Gen 4"
        var id: String { rawValue }
    }

    private var categoryNames: [(Int32, String)] {
        switch generation {
        case .gen3:
            return [(0, "Starters"), (1, "Fossils"), (2, "Gifts"), (3, "Game Corner"),
                    (4, "Stationary"), (5, "Legends"), (6, "Events"), (7, "Roamers"),
                    (8, "XD/Colo"), (9, "Channel")]
        case .gen4:
            return [(0, "Starters"), (1, "Fossils"), (2, "Gifts"), (3, "Game Corner"),
                    (4, "Stationary"), (5, "Legends"), (6, "Events"), (7, "Roamers")]
        }
    }

    private var templates: [PFStaticTemplateSwift] {
        switch generation {
        case .gen3: return PFBridge.getStaticEncounters3(type: category)
        case .gen4: return PFBridge.getStaticEncounters4(type: category)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Generation", selection: $generation) {
                    ForEach(StaticBrowserGen.allCases) { g in Text(g.rawValue).tag(g) }
                }
                .pickerStyle(.segmented)
                .onChange(of: generation) {
                    let cats = categoryNames
                    if !cats.contains(where: { $0.0 == category }) {
                        category = cats.first?.0 ?? 0
                    }
                }

                Picker("Category", selection: $category) {
                    ForEach(categoryNames, id: \.0) { cat in
                        Text(cat.1).tag(cat.0)
                    }
                }

                let list = templates
                if list.isEmpty {
                    ContentUnavailableView("No Encounters",
                                           systemImage: "sparkles",
                                           description: Text("No static encounters for this category."))
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(list) { tmpl in
                            HStack {
                                Text(tmpl.specieName)
                                    .font(.body)
                                Spacer()
                                Text("Lv. \(tmpl.level)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(gameLabel(tmpl.game))
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func gameLabel(_ game: UInt32) -> String {
        let mapping: [(UInt32, String)] = [
            (1, "R"), (2, "S"), (3, "RS"), (4, "E"), (7, "RSE"),
            (8, "FR"), (16, "LG"), (24, "FRLG"),
            (32, "XD"), (64, "Colo"),
            (128, "D"), (256, "P"), (384, "DP"), (512, "Pt"), (896, "DPPt"),
            (1024, "HG"), (2048, "SS"), (3072, "HGSS"),
        ]
        for (val, name) in mapping {
            if game == val { return name }
        }
        if game & 7 != 0 { return "RSE" }
        if game & 24 != 0 { return "FRLG" }
        if game & 896 != 0 { return "DPPt" }
        if game & 3072 != 0 { return "HGSS" }
        return String(format: "0x%X", game)
    }
}
