import SwiftUI

// MARK: - GameCube RNG View

enum GameCubeGame: String, CaseIterable, Identifiable {
    case colosseum = "Colosseum"
    case xd = "XD: Gales of Darkness"
    var id: String { rawValue }
    var pfGameValue: UInt32 {
        switch self {
        case .colosseum: return PFGame.colosseum.rawValue
        case .xd: return PFGame.gales.rawValue
        }
    }
}

enum GameCubeMode: String, CaseIterable, Identifiable {
    case shadow = "Shadow"
    case nonShadow = "Non-Shadow"
    case channel = "Channel Jirachi"
    var id: String { rawValue }
}

struct GameCubeRNGView: View {
    @State private var selectedGame: GameCubeGame = .xd
    @State private var mode: GameCubeMode = .shadow

    // Profile
    @State private var tid: UInt16 = 0
    @State private var sid: UInt16 = 0
    @State private var savedProfiles: [FinderProfile] = FinderProfileStore.load()
    @State private var selectedProfileID: UUID? = FinderProfileStore.lastProfileID

    // Seed & Advances
    @State private var seedText = ""
    @State private var initialAdvances: Int = 0
    @State private var maxAdvances: Int = 10000

    // Shadow
    @State private var shadowTemplates: [PFBridge.ShadowTemplateInfo] = []
    @State private var selectedShadowIndex: Int = 0
    @State private var unset: Bool = false

    // Non-shadow static (type 8 = gales/colo, type 9 = channel)
    @State private var staticTemplates: [PFStaticTemplateSwift] = []
    @State private var selectedStaticIndex: Int = 0

    // Filters
    @State private var selectedNatures: Set<UInt8> = []
    @State private var shinyOnly: Bool = false

    // Results
    @State private var results: [PFBridge.GameCubeResult] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Game", selection: $selectedGame) {
                    ForEach(GameCubeGame.allCases) { g in Text(g.rawValue).tag(g) }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedGame) { loadTemplates() }

                Picker("Mode", selection: $mode) {
                    ForEach(GameCubeMode.allCases) { m in Text(m.rawValue).tag(m) }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { loadTemplates() }

                // Profile
                RNGSection(title: "Trainer", icon: "person") {
                    if !savedProfiles.isEmpty {
                        Picker("Profile", selection: $selectedProfileID) {
                            Text("None").tag(UUID?.none)
                            ForEach(savedProfiles) { p in
                                Text(p.displayName).tag(UUID?.some(p.id))
                            }
                        }
                        .onChange(of: selectedProfileID) {
                            if let pid = selectedProfileID,
                               let profile = savedProfiles.first(where: { $0.id == pid }) {
                                tid = profile.tid
                                sid = profile.sid
                            }
                        }
                    }
                    FinderUInt16Field(label: "TID", value: $tid)
                    FinderUInt16Field(label: "SID", value: $sid)
                }

                // Seed
                RNGSection(title: "Seed", icon: "number") {
                    HStack {
                        Text("Seed")
                        Spacer()
                        TextField("Hex", text: $seedText)
                            .textFieldStyle(.roundedBorder).frame(width: 120)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                    }
                    RNGIntField(label: "Initial Advance", value: $initialAdvances)
                    RNGIntField(label: "Max Advance", value: $maxAdvances)
                }

                // Pokemon selection
                if mode == .shadow {
                    shadowPicker
                } else if mode == .nonShadow {
                    staticPicker
                }

                FinderNatureGrid(selected: $selectedNatures)

                Toggle("Shiny Only", isOn: $shinyOnly)
                    .padding(.horizontal)

                Button {
                    generate()
                } label: {
                    Label("Generate", systemImage: "sparkles")
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if !results.isEmpty {
                    resultsSection
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        .onAppear { loadTemplates() }
    }

    private var filteredShadowTemplates: [PFBridge.ShadowTemplateInfo] {
        shadowTemplates.filter { t in
            if selectedGame == .colosseum { return t.isColosseum }
            return !t.isColosseum
        }
    }

    private var shadowPicker: some View {
        RNGSection(title: "Shadow Pokemon", icon: "flame") {
            let filtered = filteredShadowTemplates
            if filtered.isEmpty {
                Text("No shadow templates available")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Pokemon", selection: $selectedShadowIndex) {
                    ForEach(filtered) { t in
                        Text("\(t.specieName) (Lv. \(t.level))")
                            .tag(t.id)
                    }
                }
                if selectedGame == .xd {
                    Toggle("1st Shadow Unset", isOn: $unset)
                }
            }
        }
    }

    private var staticPicker: some View {
        RNGSection(title: "Static Pokemon", icon: "star") {
            if staticTemplates.isEmpty {
                Text("No static templates available")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Pokemon", selection: $selectedStaticIndex) {
                    ForEach(Array(staticTemplates.enumerated()), id: \.offset) { idx, t in
                        Text("\(t.specieName) (Lv. \(t.level))")
                            .tag(idx)
                    }
                }
            }
        }
    }

    private var resultsSection: some View {
        RNGSection(title: "Results (\(results.count))", icon: "list.bullet") {
            ForEach(results.prefix(500)) { r in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Adv: \(r.advances)")
                            .font(.system(.caption, design: .monospaced))
                        Spacer()
                        if r.shiny > 0 {
                            Image(systemName: "star.fill")
                                .font(.caption2).foregroundStyle(.yellow)
                        }
                    }
                    HStack {
                        Text("PID: \(String(format: "%08X", r.pid))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(pfNatureNames[Int(r.nature)])
                            .font(.caption2).bold()
                        Text(r.gender == 0 ? "♂" : r.gender == 1 ? "♀" : "-")
                            .font(.caption2)
                    }
                    Text("IVs: \(r.ivs.map(String.init).joined(separator: "/"))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("HP: \(hiddenPowerTypes[Int(r.hiddenPower)])")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("(\(r.hiddenPowerStrength))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                Divider()
            }
        }
    }

    private func loadTemplates() {
        if mode == .shadow {
            if shadowTemplates.isEmpty {
                shadowTemplates = PFBridge.getShadowTemplates()
            }
            let filtered = filteredShadowTemplates
            if !filtered.isEmpty && !filtered.contains(where: { $0.id == selectedShadowIndex }) {
                selectedShadowIndex = filtered[0].id
            }
        } else if mode == .nonShadow {
            staticTemplates = PFBridge.getStaticEncounters3(type: 8)
            selectedStaticIndex = 0
        } else {
            staticTemplates = PFBridge.getStaticEncounters3(type: 9)
            selectedStaticIndex = 0
        }
    }

    private func generate() {
        let seed = UInt32(seedText, radix: 16) ?? 0
        let initAdv = UInt32(initialAdvances)
        let maxAdv = UInt32(maxAdvances)
        let tID = tid, sID = sid
        let gameVal = selectedGame.pfGameValue
        let shiny: UInt8 = shinyOnly ? 1 : 255
        var natArr = [Bool](repeating: selectedNatures.isEmpty, count: 25)
        for n in selectedNatures { natArr[Int(n)] = true }

        let currentMode = mode
        let shadowIdx = selectedShadowIndex
        let isUnset = unset
        let staticIdx = selectedStaticIndex

        searchTask = Task.detached {
            let r: [PFBridge.GameCubeResult]
            switch currentMode {
            case .shadow:
                r = PFBridge.gamecubeGenerateShadow(
                    seed: seed, initialAdvances: initAdv, maxAdvances: maxAdv,
                    shadowIndex: shadowIdx, unset: isUnset,
                    tid: tID, sid: sID, game: gameVal,
                    filterShiny: shiny, natures: natArr)
            case .nonShadow:
                r = PFBridge.gamecubeGenerateStatic(
                    seed: seed, initialAdvances: initAdv, maxAdvances: maxAdv,
                    method: .xdColo, staticType: 8, staticIndex: staticIdx,
                    tid: tID, sid: sID, game: gameVal,
                    filterShiny: shiny, natures: natArr)
            case .channel:
                r = PFBridge.gamecubeGenerateStatic(
                    seed: seed, initialAdvances: initAdv, maxAdvances: maxAdv,
                    method: .channel, staticType: 9, staticIndex: 0,
                    tid: tID, sid: sID, game: PFGame.gales.rawValue,
                    filterShiny: shiny, natures: natArr)
            }
            await MainActor.run { results = r }
        }
    }
}
