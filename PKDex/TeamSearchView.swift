//
//  TeamSearchView.swift
//  PKDex
//
//  The Team Search tab: describe a team idea, and see the tournament teams
//  that match, grouped into compositions. The list shows the parsed query
//  as chips, then Smogon's "often paired with" suggestions, then the
//  compositions and where the data came from. A composition opens its
//  teams, and a team opens the same team sheet the Tournaments tab uses,
//  with its save buttons.
//

import SwiftUI

struct TeamSearchView: View {
    @State private var model = TeamSearchModel()
    @State private var text = ""
    @State private var selection: TeamComposition.ID?
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        // Wide layouts get a list/detail split; compact keeps push navigation.
        if hSize == .regular {
            NavigationSplitView {
                screen(selection: $selection)
            } detail: {
                NavigationStack {
                    if let composition = model.results.first(where: { $0.id == selection }) {
                        CompositionDetailView(composition: composition, insights: model.insights)
                    } else {
                        ContentUnavailableView {
                            Label("Select a Composition", systemImage: "sidebar.left")
                        } description: {
                            Text("Choose a composition to see its teams.")
                        }
                    }
                }
            }
        } else {
            NavigationStack {
                screen(selection: nil)
            }
        }
    }

    private func screen(selection: Binding<TeamComposition.ID?>?) -> some View {
        content(selection: selection)
            .navigationTitle("Team Search")
            .searchable(text: $text, prompt: "Trick Room with Mega Gardevoir, no Incineroar")
            .autocorrectionDisabled()
            .onSubmit(of: .search) { model.setText(text) }
            .task(id: text) {
                // Waits for a pause in typing before searching.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                model.setText(text)
            }
            .task(id: model.regulation) { await model.load() }
            .refreshable { await model.load(forceRefresh: true) }
            .toolbar {
                if model.isRefreshing {
                    ToolbarItem(placement: .status) {
                        ProgressView().controlSize(.small)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Regulation", selection: $model.regulation) {
                            ForEach(ChampionsRegulation.allCases) { regulation in
                                Text(regulation.displayName).tag(regulation)
                            }
                        }
                    } label: {
                        Label(model.regulation.displayName, systemImage: "calendar")
                    }
                }
            }
    }

    @ViewBuilder
    private func content(selection: Binding<TeamComposition.ID?>?) -> some View {
        switch model.status {
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't Load Teams", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await model.load(forceRefresh: true) } }
            }
        case .idle, .loading:
            loading
        case .ready:
            if let selection {
                List(selection: selection) { sections(selectable: true) }
            } else {
                List { sections(selectable: false) }
            }
        }
    }

    private var loading: some View {
        VStack(spacing: 12) {
            if case .loading(let completed, let total) = model.status, total > 0 {
                ProgressView(value: Double(completed), total: Double(total))
                    .frame(maxWidth: 240)
                Text("Loading tournament teams… \(completed) of \(total) events")
            } else {
                ProgressView()
                Text("Loading tournament teams…")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding()
    }

    @ViewBuilder
    private func sections(selectable: Bool) -> some View {
        let chips = model.chips
        if !chips.isEmpty {
            Section {
                QueryChips(chips: chips, invert: model.invert, remove: model.remove)
            } footer: {
                Text("Tap a chip to switch between include and exclude.")
            }
        }

        if !model.suggestions.isEmpty, let insights = model.insights {
            Section {
                Suggestions(suggestions: model.suggestions) { suggestion in
                    // Added to the text, so it survives further typing.
                    text = text.isEmpty ? suggestion.term.displayName
                                        : text + ", " + suggestion.term.displayName
                    model.setText(text)
                }
            } header: {
                Text("Often paired with")
            } footer: {
                Text(suggestionsFooter(insights))
            }
        }

        if let refreshError = model.refreshError {
            Section {
                Label(refreshError, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }

        Section {
            if model.results.isEmpty {
                ContentUnavailableView {
                    Label("No Matching Teams", systemImage: "magnifyingglass")
                } description: {
                    Text("Try removing a requirement.")
                }
            }
            ForEach(model.results) { composition in
                if selectable {
                    CompositionRow(composition: composition).tag(composition.id)
                } else {
                    NavigationLink {
                        CompositionDetailView(composition: composition, insights: model.insights)
                    } label: {
                        CompositionRow(composition: composition)
                    }
                }
            }
        } header: {
            Text(resultsHeader)
        } footer: {
            sourceFooter
        }
    }

    private var resultsHeader: String {
        guard model.query.hasConstraints else { return "Popular compositions" }
        let teams = model.results.reduce(0) { $0 + $1.teams.count }
        return "\(plural(model.results.count, "composition")) · \(plural(teams, "team"))"
    }

    private var sourceFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let updatedAt = model.updatedAt {
                Text("From \(plural(model.teamCount, "team")) at \(plural(model.eventCount, "event")) with 16+ players, updated \(updatedAt, format: .relative(presentation: .named)).")
            }
            if model.missingEventCount > 0 {
                Text("\(plural(model.missingEventCount, "event")) couldn't be loaded. Pull to refresh to try again.")
            }
            Link("Tournament teams from Limitless", destination: URL(string: "https://play.limitlesstcg.com")!)
            if model.insights != nil {
                Link("Usage stats from Smogon", destination: URL(string: "https://www.smogon.com/stats/")!)
            }
        }
    }

    private func suggestionsFooter(_ insights: SmogonInsights) -> String {
        let requested = model.query.species.count == 1
            ? "teams with \(model.query.species[0].displayName)"
            : "teams with each of them (the lowest share is shown)"
        var text = "Share of Smogon ladder \(requested) that also run it. " + usageLabel(insights.usage)
        if let statsRegulation = insights.usage.regulation, statsRegulation != model.regulation {
            text += " \(model.regulation.displayName) stats aren't published yet."
        }
        return text
    }
}

// MARK: - Suggestions

private struct Suggestions: View {
    let suggestions: [SmogonInsights.Suggestion]
    let add: (SmogonInsights.Suggestion) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(suggestions) { suggestion in
                Button {
                    add(suggestion)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption2.weight(.bold))
                        Text(suggestion.term.displayName)
                            .font(.caption.weight(.medium))
                        Text(percent(suggestion.share))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.fill.tertiary, in: Capsule())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add \(suggestion.term.displayName), \(percent(suggestion.share))")
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Chips

private struct QueryChips: View {
    let chips: [TeamSearchModel.Chip]
    let invert: (TeamSearchModel.Chip) -> Void
    let remove: (TeamSearchModel.Chip) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(chips) { chip in
                HStack(spacing: 4) {
                    Image(systemName: icon(for: chip))
                        .font(.caption2)
                    Text(chip.label)
                        .font(.caption.weight(.medium))
                    Button {
                        remove(chip)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.bold))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(chip.label)")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(color(for: chip))
                .background(color(for: chip).opacity(0.14), in: Capsule())
                .contentShape(Capsule())
                .onTapGesture {
                    if chip.canInvert { invert(chip) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(chip.canInvert ? .isButton : [])
                .accessibilityHint(chip.canInvert
                                   ? (chip.isExcluded ? "Includes it instead" : "Excludes it instead")
                                   : "")
            }
        }
        .padding(.vertical, 2)
    }

    private func icon(for chip: TeamSearchModel.Chip) -> String {
        switch chip {
        case .species(_, let excluded): return excluded ? "minus.circle" : "checkmark.circle"
        case .move(_, let excluded): return excluded ? "minus.circle" : "bolt"
        case .style(_, let excluded): return excluded ? "minus.circle" : "sparkles"
        case .correction: return "wand.and.stars"
        case .unrecognized: return "questionmark.circle"
        }
    }

    private func color(for chip: TeamSearchModel.Chip) -> Color {
        switch chip {
        case .correction: return .blue
        case .unrecognized: return .secondary
        default: return chip.isExcluded ? .red : .accentColor
        }
    }
}

// MARK: - Composition row

private struct CompositionRow: View {
    let composition: TeamComposition

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SpeciesChips(species: composition.species)
            if !composition.tags.isEmpty || composition.isPartial {
                StyleTags(tags: composition.tags, partial: composition.isPartial)
            }
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var summary: String {
        var parts = [plural(composition.teams.count, "team"), plural(composition.eventCount, "event")]
        if let best = composition.bestTeam { parts.append("best " + finish(best)) }
        return parts.joined(separator: " · ")
    }
}

private struct SpeciesChips: View {
    let species: [String]

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(Array(species.enumerated()), id: \.offset) { _, name in
                Text(name)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.fill.tertiary, in: Capsule())
            }
        }
    }
}

private struct StyleTags: View {
    let tags: [TeamArchetype]
    let partial: Bool

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(tags) { tag in
                Text(tag.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(.tint)
                    .background(.tint.opacity(0.12), in: Capsule())
            }
            if partial {
                Text("Partial match")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(.orange)
                    .background(.orange.opacity(0.12), in: Capsule())
            }
        }
    }
}

// MARK: - Composition detail

struct CompositionDetailView: View {
    let composition: TeamComposition
    let insights: SmogonInsights?

    var body: some View {
        List {
            Section {
                SpeciesChips(species: composition.species)
                if !composition.tags.isEmpty || composition.isPartial {
                    StyleTags(tags: composition.tags, partial: composition.isPartial)
                }
            }

            if !composition.reasons.isEmpty {
                Section("Why It Matched") {
                    ForEach(composition.reasons, id: \.self) { reason in
                        Text(reason)
                    }
                }
            }

            Section("Summary") {
                LabeledContent("Teams", value: "\(composition.teams.count)")
                LabeledContent("Events", value: "\(composition.eventCount)")
                if let best = composition.bestTeam {
                    LabeledContent("Best finish", value: finish(best))
                }
            }

            if let insights {
                Section {
                    ForEach(Array(zip(composition.species, composition.speciesIDs).enumerated()),
                            id: \.offset) { _, pair in
                        LabeledContent(pair.0,
                                       value: insights.usage(ofSpecies: pair.1).map(percent) ?? "—")
                    }
                } header: {
                    Text("Ladder Usage")
                } footer: {
                    Text("Share of Smogon ladder teams running each Pokémon. " + usageLabel(insights.usage))
                }
            }

            if !composition.variants.isEmpty {
                Section {
                    ForEach(Array(composition.variants.enumerated()), id: \.offset) { _, variant in
                        HStack {
                            Text((variant.added.map { "+ " + $0 } + variant.removed.map { "− " + $0 })
                                .joined(separator: "   "))
                            Spacer()
                            Text(plural(variant.teams.count, "team"))
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                } header: {
                    Text("Variants")
                } footer: {
                    Text("Teams that swap one Pokémon from the composition above.")
                }
            }

            Section("Teams (\(composition.teams.count))") {
                ForEach(composition.teams) { team in
                    NavigationLink {
                        StandingDetailView(standing: team.team.team.standing)
                    } label: {
                        TeamResultRow(team: team)
                    }
                }
            }
        }
        .navigationTitle("Composition")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TeamResultRow: View {
    let team: ScoredTeam

    var body: some View {
        let corpusTeam = team.team.team
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(corpusTeam.standing.name)
                    .font(.body.weight(.medium))
                Spacer()
                Text(finish(team))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text("\(corpusTeam.tournament.name) · \(corpusTeam.tournament.displayDate)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if team.isPartial {
                Text("Missing " + team.missing.map(\.displayName).joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - Formatting

/// "1st of 388", or "Unranked" for a player who dropped.
private func finish(_ team: ScoredTeam) -> String {
    let corpusTeam = team.team.team
    guard let placing = corpusTeam.standing.placing else { return "Unranked" }
    let formatter = NumberFormatter()
    formatter.numberStyle = .ordinal
    let ordinal = formatter.string(from: placing as NSNumber) ?? "#\(placing)"
    return "\(ordinal) of \(corpusTeam.tournament.players)"
}

/// "44%".
private func percent(_ share: Double) -> String {
    share.formatted(.percent.precision(.fractionLength(0)))
}

/// Which stats these are: "Reg M-B, August 2026, 1760+ ladder."
private func usageLabel(_ usage: SmogonUsage) -> String {
    var parts: [String] = []
    if let regulation = usage.regulation { parts.append(regulation.displayName) }
    let parser = DateFormatter()
    parser.dateFormat = "yyyy-MM"
    parser.locale = Locale(identifier: "en_US_POSIX")
    if let date = parser.date(from: usage.month) {
        parts.append(date.formatted(.dateTime.month(.wide).year()))
    } else {
        parts.append(usage.month)
    }
    parts.append("\(usage.rating)+ ladder")
    return parts.joined(separator: ", ") + "."
}

/// "1 team", "3 teams".
private func plural(_ count: Int, _ noun: String) -> String {
    "\(count) \(noun)\(count == 1 ? "" : "s")"
}
