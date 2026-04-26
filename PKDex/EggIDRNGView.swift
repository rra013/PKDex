import SwiftUI

// MARK: - Egg RNG View

struct EggRNGView: View {
    @State private var generation: FinderGeneration = .gen3
    @State private var selectedGame: FinderGameVersion = .emerald

    // Profile
    @State private var tid: UInt16 = 0
    @State private var sid: UInt16 = 0
    @State private var savedProfiles: [FinderProfile] = FinderProfileStore.load()
    @State private var selectedProfileID: UUID? = FinderProfileStore.lastProfileID

    // Seeds
    @State private var seedHeldText = ""
    @State private var seedPickupText = ""

    // Advances
    @State private var initialAdvances: Int = 0
    @State private var maxAdvances: Int = 10000
    @State private var initialAdvancesPickup: Int = 0
    @State private var maxAdvancesPickup: Int = 10000

    // Emerald-specific
    @State private var calibration: Int = 0
    @State private var minRedraw: Int = 0
    @State private var maxRedraw: Int = 0

    // Parent A
    @State private var parentAHP: UInt8 = 31
    @State private var parentAAtk: UInt8 = 31
    @State private var parentADef: UInt8 = 31
    @State private var parentASpA: UInt8 = 31
    @State private var parentASpD: UInt8 = 31
    @State private var parentASpe: UInt8 = 31
    @State private var parentAAbility: UInt8 = 0
    @State private var parentAGender: UInt8 = 0
    @State private var parentAItem: UInt8 = 0
    @State private var parentANature: UInt8 = 0

    // Parent B
    @State private var parentBHP: UInt8 = 31
    @State private var parentBAtk: UInt8 = 31
    @State private var parentBDef: UInt8 = 31
    @State private var parentBSpA: UInt8 = 31
    @State private var parentBSpD: UInt8 = 31
    @State private var parentBSpe: UInt8 = 31
    @State private var parentBAbility: UInt8 = 0
    @State private var parentBGender: UInt8 = 1
    @State private var parentBItem: UInt8 = 0
    @State private var parentBNature: UInt8 = 0

    // Egg species
    @State private var eggSpecie: Int = 1
    @State private var masuda: Bool = false
    @State private var compatibility: Int = 20

    // Filters
    @State private var selectedNatures: Set<UInt8> = []
    @State private var shinyOnly: Bool = false

    // Results
    @State private var results3: [PFBridge.EggResult3] = []
    @State private var results4: [PFBridge.EggResult4] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Generation", selection: $generation) {
                    ForEach(FinderGeneration.allCases) { g in Text(g.rawValue).tag(g) }
                }
                .pickerStyle(.segmented)
                .onChange(of: generation) {
                    let games = FinderGameVersion.games(for: generation)
                    if !games.contains(selectedGame) { selectedGame = games[0] }
                }

                Picker("Game", selection: $selectedGame) {
                    ForEach(FinderGameVersion.games(for: generation)) { g in
                        Text(g.rawValue).tag(g)
                    }
                }

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

                // Seeds
                RNGSection(title: "Seeds", icon: "number") {
                    HStack {
                        Text("Held Seed")
                        Spacer()
                        TextField("Hex", text: $seedHeldText)
                            .textFieldStyle(.roundedBorder).frame(width: 120)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                    }
                    HStack {
                        Text("Pickup Seed")
                        Spacer()
                        TextField("Hex", text: $seedPickupText)
                            .textFieldStyle(.roundedBorder).frame(width: 120)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                    }
                    RNGIntField(label: "Initial Advance", value: $initialAdvances)
                    RNGIntField(label: "Max Advance", value: $maxAdvances)
                    RNGIntField(label: "Pickup Init Adv", value: $initialAdvancesPickup)
                    RNGIntField(label: "Pickup Max Adv", value: $maxAdvancesPickup)

                    if generation == .gen3 && selectedGame == .emerald {
                        RNGIntField(label: "Calibration", value: $calibration)
                        RNGIntField(label: "Min Redraw", value: $minRedraw)
                        RNGIntField(label: "Max Redraw", value: $maxRedraw)
                    }
                }

                // Daycare
                RNGSection(title: "Daycare", icon: "house") {
                    Picker("Compatibility", selection: $compatibility) {
                        Text("The two seem to get along (20%)").tag(20)
                        Text("The two seem to get along very well (50%)").tag(50)
                        Text("The two don't seem to like each other (70%)").tag(70)
                    }

                    Toggle("Masuda Method", isOn: $masuda)

                    HStack {
                        Text("Egg Species #")
                        Spacer()
                        TextField("", value: $eggSpecie, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 80)
                            .multilineTextAlignment(.trailing)
                    }
                }

                parentSection(label: "Parent A",
                              hp: $parentAHP, atk: $parentAAtk, def: $parentADef,
                              spa: $parentASpA, spd: $parentASpD, spe: $parentASpe,
                              ability: $parentAAbility, gender: $parentAGender,
                              item: $parentAItem, nature: $parentANature)

                parentSection(label: "Parent B",
                              hp: $parentBHP, atk: $parentBAtk, def: $parentBDef,
                              spa: $parentBSpA, spd: $parentBSpD, spe: $parentBSpe,
                              ability: $parentBAbility, gender: $parentBGender,
                              item: $parentBItem, nature: $parentBNature)

                FinderNatureGrid(selected: $selectedNatures)

                Toggle("Shiny Only", isOn: $shinyOnly)
                    .padding(.horizontal)

                Button {
                    generateEggs()
                } label: {
                    Label("Generate", systemImage: "sparkles")
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if generation == .gen3 && !results3.isEmpty {
                    eggResults3Section
                }
                if generation == .gen4 && !results4.isEmpty {
                    eggResults4Section
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    }

    private func parentSection(label: String,
                                hp: Binding<UInt8>, atk: Binding<UInt8>, def: Binding<UInt8>,
                                spa: Binding<UInt8>, spd: Binding<UInt8>, spe: Binding<UInt8>,
                                ability: Binding<UInt8>, gender: Binding<UInt8>,
                                item: Binding<UInt8>, nature: Binding<UInt8>) -> some View {
        RNGSection(title: label, icon: "figure.stand") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                IVSliderRow8(label: "HP", value: hp)
                IVSliderRow8(label: "Atk", value: atk)
                IVSliderRow8(label: "Def", value: def)
                IVSliderRow8(label: "SpA", value: spa)
                IVSliderRow8(label: "SpD", value: spd)
                IVSliderRow8(label: "Spe", value: spe)
            }

            Picker("Gender", selection: gender) {
                Text("Male").tag(UInt8(0))
                Text("Female").tag(UInt8(1))
                Text("Ditto").tag(UInt8(3))
            }

            Picker("Ability", selection: ability) {
                Text("Ability 0").tag(UInt8(0))
                Text("Ability 1").tag(UInt8(1))
            }

            Picker("Nature", selection: nature) {
                ForEach(0..<25, id: \.self) { i in
                    Text(pfNatureNames[i]).tag(UInt8(i))
                }
            }

            Picker("Held Item", selection: item) {
                Text("None").tag(UInt8(0))
                Text("Everstone").tag(UInt8(1))
                Text("Power Weight (HP)").tag(UInt8(2))
                Text("Power Bracer (Atk)").tag(UInt8(3))
                Text("Power Belt (Def)").tag(UInt8(4))
                Text("Power Lens (SpA)").tag(UInt8(5))
                Text("Power Band (SpD)").tag(UInt8(6))
                Text("Power Anklet (Spe)").tag(UInt8(7))
            }
        }
    }

    private var eggResults3Section: some View {
        RNGSection(title: "Results (\(results3.count))", icon: "list.bullet") {
            ForEach(results3.prefix(500)) { r in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Adv: \(r.advances)")
                            .font(.system(.caption, design: .monospaced))
                        Spacer()
                        Text("Pickup: \(r.pickupAdvances)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("PID: \(String(format: "%08X", r.pid))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(pfNatureNames[Int(r.nature)]).font(.caption2).bold()
                        if r.shiny > 0 {
                            Image(systemName: "star.fill")
                                .font(.caption2).foregroundStyle(.yellow)
                        }
                    }
                    Text("IVs: \(r.ivs.map(String.init).joined(separator: "/"))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("Inherit: \(inheritanceString(r.inheritance))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Divider()
            }
        }
    }

    private var eggResults4Section: some View {
        RNGSection(title: "Results (\(results4.count))", icon: "list.bullet") {
            ForEach(results4.prefix(500)) { r in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Adv: \(r.advances)")
                            .font(.system(.caption, design: .monospaced))
                        Spacer()
                        Text("Pickup: \(r.pickupAdvances)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("PID: \(String(format: "%08X", r.pid))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(pfNatureNames[Int(r.nature)]).font(.caption2).bold()
                        if r.chatot > 0 {
                            Text("C:\(r.chatot)").font(.caption2).foregroundStyle(.orange)
                        }
                        if r.shiny > 0 {
                            Image(systemName: "star.fill")
                                .font(.caption2).foregroundStyle(.yellow)
                        }
                    }
                    Text("IVs: \(r.ivs.map(String.init).joined(separator: "/"))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("Inherit: \(inheritanceString(r.inheritance))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Divider()
            }
        }
    }

    private func inheritanceString(_ inh: [UInt8]) -> String {
        let labels = ["HP", "Atk", "Def", "SpA", "SpD", "Spe"]
        return (0..<6).map { i in
            switch inh[i] {
            case 1: return "\(labels[i]):A"
            case 2: return "\(labels[i]):B"
            default: return "\(labels[i]):R"
            }
        }.joined(separator: " ")
    }

    private func generateEggs() {
        let gen = generation
        let seedH = UInt32(seedHeldText, radix: 16) ?? 0
        let seedP = UInt32(seedPickupText, radix: 16) ?? 0
        let tID = tid, sID = sid
        let initAdv = UInt32(initialAdvances), maxAdv = UInt32(maxAdvances)
        let initAdvP = UInt32(initialAdvancesPickup), maxAdvP = UInt32(maxAdvancesPickup)
        let cal = UInt8(calibration), minR = UInt8(minRedraw), maxR = UInt8(maxRedraw)
        let compat = UInt8(compatibility)
        let pAIVs = [parentAHP, parentAAtk, parentADef, parentASpA, parentASpD, parentASpe]
        let pBIVs = [parentBHP, parentBAtk, parentBDef, parentBSpA, parentBSpD, parentBSpe]
        let pAA = parentAAbility, pBA = parentBAbility
        let pAG = parentAGender, pBG = parentBGender
        let pAI = parentAItem, pBI = parentBItem
        let pAN = parentANature, pBN = parentBNature
        let spec = UInt16(eggSpecie)
        let mas = masuda
        let gameVal = selectedGame.pfGame
        let isDeadBattery = selectedGame == .emerald
        let shiny = shinyOnly
        var natArr = [Bool](repeating: selectedNatures.isEmpty, count: 25)
        for n in selectedNatures { natArr[Int(n)] = true }
        let shinyFilter: UInt8 = shiny ? 1 : 255

        let eggMethod: PFMethod = (selectedGame == .emerald) ? .eBred : .rsFRLGBred

        searchTask = Task.detached {
            if gen == .gen3 {
                let r = PFBridge.eggGenerate3(
                    seedHeld: seedH, seedPickup: seedP,
                    initialAdvances: initAdv, maxAdvances: maxAdv,
                    initialAdvancesPickup: initAdvP, maxAdvancesPickup: maxAdvP,
                    calibration: cal, minRedraw: minR, maxRedraw: maxR,
                    method: eggMethod, compatibility: compat,
                    parentAIVs: pAIVs, parentBIVs: pBIVs,
                    parentAAbility: pAA, parentBAbility: pBA,
                    parentAGender: pAG, parentBGender: pBG,
                    parentAItem: pAI, parentBItem: pBI,
                    parentANature: pAN, parentBNature: pBN,
                    eggSpecie: spec, masuda: mas,
                    tid: tID, sid: sID,
                    game: UInt8(gameVal.rawValue), deadBattery: isDeadBattery,
                    filterShiny: shinyFilter, natures: natArr)
                await MainActor.run { results3 = r }
            } else {
                let r = PFBridge.eggGenerate4(
                    seedHeld: seedH, seedPickup: seedP,
                    initialAdvances: initAdv, maxAdvances: maxAdv,
                    initialAdvancesPickup: initAdvP, maxAdvancesPickup: maxAdvP,
                    parentAIVs: pAIVs, parentBIVs: pBIVs,
                    parentAAbility: pAA, parentBAbility: pBA,
                    parentAGender: pAG, parentBGender: pBG,
                    parentAItem: pAI, parentBItem: pBI,
                    parentANature: pAN, parentBNature: pBN,
                    eggSpecie: spec, masuda: mas,
                    tid: tID, sid: sID,
                    game: UInt8(gameVal.rawValue),
                    filterShiny: shinyFilter, natures: natArr)
                await MainActor.run { results4 = r }
            }
        }
    }
}

// MARK: - ID RNG View

struct IDRNGView: View {
    @State private var generation: FinderGeneration = .gen3
    @State private var selectedGame: FinderGameVersion = .emerald

    // Gen 3
    @State private var gen3SeedText = ""
    @State private var gen3TID: UInt16 = 0
    @State private var gen3InitAdvance: Int = 0
    @State private var gen3MaxAdvance: Int = 100000

    // Gen 4
    @State private var gen4MinDelay: Int = 500
    @State private var gen4MaxDelay: Int = 10000
    @State private var gen4Year: Int = 2000
    @State private var gen4Month: Int = 1
    @State private var gen4Day: Int = 1
    @State private var gen4Hour: Int = 0
    @State private var gen4Minute: Int = 0
    @State private var gen4TargetTID: UInt16 = 0
    @State private var gen4FilterTID: Bool = false
    @State private var gen4TargetSID: UInt16 = 0
    @State private var gen4FilterSID: Bool = false

    // Results
    @State private var results3: [PFBridge.IDResult] = []
    @State private var results4: [PFBridge.IDResult4] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Generation", selection: $generation) {
                    ForEach(FinderGeneration.allCases) { g in Text(g.rawValue).tag(g) }
                }
                .pickerStyle(.segmented)
                .onChange(of: generation) {
                    let games = FinderGameVersion.games(for: generation)
                    if !games.contains(selectedGame) { selectedGame = games[0] }
                }

                Picker("Game", selection: $selectedGame) {
                    ForEach(FinderGameVersion.games(for: generation)) { g in
                        Text(g.rawValue).tag(g)
                    }
                }

                if generation == .gen3 {
                    gen3Inputs
                } else {
                    gen4Inputs
                }

                Button {
                    generateIDs()
                } label: {
                    Label("Generate", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if generation == .gen3 && !results3.isEmpty {
                    idResults3Section
                }
                if generation == .gen4 && !results4.isEmpty {
                    idResults4Section
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    }

    private var gen3Inputs: some View {
        RNGSection(title: "Gen 3 ID Generation", icon: "number") {
            if selectedGame == .ruby || selectedGame == .sapphire {
                HStack {
                    Text("Initial Seed")
                    Spacer()
                    TextField("Hex", text: $gen3SeedText)
                        .textFieldStyle(.roundedBorder).frame(width: 120)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                }
            } else {
                FinderUInt16Field(label: "TID", value: $gen3TID)
                Text("FRLG/Emerald: Enter your TID to find matching SIDs")
                    .font(.caption).foregroundStyle(.secondary)
            }
            RNGIntField(label: "Initial Advance", value: $gen3InitAdvance)
            RNGIntField(label: "Max Advance", value: $gen3MaxAdvance)
        }
    }

    private var gen4Inputs: some View {
        RNGSection(title: "Gen 4 ID Generation", icon: "number") {
            RNGIntField(label: "Min Delay", value: $gen4MinDelay)
            RNGIntField(label: "Max Delay", value: $gen4MaxDelay)

            HStack {
                Text("Date")
                Spacer()
                TextField("Y", value: $gen4Year, format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 60)
                Text("/")
                TextField("M", value: $gen4Month, format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 40)
                Text("/")
                TextField("D", value: $gen4Day, format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 40)
            }

            HStack {
                Text("Time")
                Spacer()
                TextField("H", value: $gen4Hour, format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 40)
                Text(":")
                TextField("M", value: $gen4Minute, format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 40)
            }

            Toggle("Filter TID", isOn: $gen4FilterTID)
            if gen4FilterTID {
                FinderUInt16Field(label: "Target TID", value: $gen4TargetTID)
            }

            Toggle("Filter SID", isOn: $gen4FilterSID)
            if gen4FilterSID {
                FinderUInt16Field(label: "Target SID", value: $gen4TargetSID)
            }
        }
    }

    private var idResults3Section: some View {
        RNGSection(title: "Results (\(results3.count))", icon: "list.bullet") {
            ForEach(results3.prefix(500)) { r in
                HStack {
                    Text("Adv: \(r.advances)")
                        .font(.system(.caption, design: .monospaced))
                    Spacer()
                    Text("TID: \(r.tid)")
                        .font(.system(.caption, design: .monospaced))
                    Text("SID: \(r.sid)")
                        .font(.system(.caption, design: .monospaced))
                    Text("TSV: \(r.tsv)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Divider()
            }
        }
    }

    private var idResults4Section: some View {
        RNGSection(title: "Results (\(results4.count))", icon: "list.bullet") {
            ForEach(results4.prefix(500)) { r in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Seed: \(String(format: "%08X", r.seed))")
                            .font(.system(.caption, design: .monospaced))
                        Spacer()
                        Text("Delay: \(r.delay)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("TID: \(r.tid)")
                            .font(.system(.caption, design: .monospaced))
                        Text("SID: \(r.sid)")
                            .font(.system(.caption, design: .monospaced))
                        Spacer()
                        Text("TSV: \(r.tsv)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("Sec: \(r.seconds)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
            }
        }
    }

    private func generateIDs() {
        let gen = generation
        let game = selectedGame
        let seedText = gen3SeedText
        let initAdv = UInt32(gen3InitAdvance)
        let maxAdv = UInt32(gen3MaxAdvance)
        let tID = gen3TID
        let minDel = UInt32(gen4MinDelay), maxDel = UInt32(gen4MaxDelay)
        let yr = UInt16(gen4Year), mo = UInt8(gen4Month), dy = UInt8(gen4Day)
        let hr = UInt8(gen4Hour), mn = UInt8(gen4Minute)
        let targetTID = gen4TargetTID, fTID = gen4FilterTID
        let targetSID = gen4TargetSID, fSID = gen4FilterSID

        searchTask = Task.detached {
            if gen == .gen3 {
                let r: [PFBridge.IDResult]
                if game == .ruby || game == .sapphire {
                    let seed = UInt16(seedText, radix: 16) ?? 0
                    r = PFBridge.idGenerate3RS(seed: seed,
                                                initialAdvances: initAdv,
                                                maxAdvances: maxAdv)
                } else {
                    r = PFBridge.idGenerate3FRLGE(tid: tID,
                                                    initialAdvances: initAdv,
                                                    maxAdvances: maxAdv)
                }
                await MainActor.run { results3 = r }
            } else {
                let r = PFBridge.idGenerate4(
                    minDelay: minDel, maxDelay: maxDel,
                    year: yr, month: mo, day: dy,
                    hour: hr, minute: mn,
                    targetTID: targetTID, filterTID: fTID,
                    targetSID: targetSID, filterSID: fSID)
                await MainActor.run { results4 = r }
            }
        }
    }
}
