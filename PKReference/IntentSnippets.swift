//
//  IntentSnippets.swift
//  PKReference
//
//  What the App Intents show beside their spoken answers: small views for
//  Siri, Spotlight and Shortcuts, each with a button that opens the page in
//  the app. They reuse the app's type badges; the answers they show are in
//  `IntentAnswers.swift`.
//

import AppIntents
import SwiftUI

// MARK: - Snippets

struct OpenInAppLabel: View {
    var body: some View {
        Label("Open in PK Reference", systemImage: "arrow.up.forward.app")
            .frame(maxWidth: .infinity)
    }
}

struct PokemonSnippetView: View {
    let answer: PokemonLookupAnswer
    let pokemon: PokemonEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(answer.name).font(.headline)
                Spacer()
                ForEach(answer.types, id: \.self) { TypeBadge(type: $0) }
            }
            ForEach(answer.matchups, id: \.multiplier) { matchup in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(PokemonLookupAnswer.symbol(matchup.multiplier))
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                    FlowLayout(spacing: 4) {
                        ForEach(matchup.types, id: \.self) { TypeBadge(type: $0) }
                    }
                }
            }
            Text("Base stat total: \(answer.baseStatTotal)")
                .font(.caption).foregroundStyle(.secondary)
            Button(intent: OpenPokemonIntent(target: pokemon)) { OpenInAppLabel() }
                .buttonStyle(.bordered)
        }
        .padding()
    }
}

struct DamageSnippetView: View {
    let answer: DamageAnswer
    let open: OpenCalcIntent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(answer.attacker) → \(answer.defender)").font(.headline)
            Text(answer.move).font(.subheadline).foregroundStyle(.secondary)
            Text("\(DamageAnswer.percent(answer.minPercent)) – \(DamageAnswer.percent(answer.maxPercent))")
                .font(.title2.monospacedDigit().bold())
            if let knockOut = answer.knockOut {
                Text(knockOut.prefix(1).uppercased() + knockOut.dropFirst())
                    .font(.subheadline)
            }
            Text(answer.details).font(.caption).foregroundStyle(.secondary)
            Button(intent: open) { OpenInAppLabel() }
                .buttonStyle(.bordered)
        }
        .padding()
    }
}

struct TeamSearchSnippetView: View {
    let answer: TeamSearchAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(answer.compositions) compositions · \(answer.teams) teams").font(.headline)
            ForEach(Array(answer.top.enumerated()), id: \.offset) { _, composition in
                VStack(alignment: .leading, spacing: 2) {
                    Text(composition.species.joined(separator: ", ")).font(.subheadline)
                    Text("\(composition.teams) teams").font(.caption).foregroundStyle(.secondary)
                }
            }
            Button(intent: OpenTeamSearchIntent(query: answer.query)) { OpenInAppLabel() }
                .buttonStyle(.bordered)
        }
        .padding()
    }
}

struct SpeedSnippetView: View {
    let answer: SpeedAnswer
    let open: OpenSpeedTiersIntent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(answer.first, faster: answer.first.speed > answer.second.speed)
            row(answer.second, faster: answer.second.speed > answer.first.speed)
            if answer.first.speed == answer.second.speed {
                Text("Speed tie: either could move first.").font(.subheadline)
            }
            Text(answer.details).font(.caption).foregroundStyle(.secondary)
            Button(intent: open) { OpenInAppLabel() }
                .buttonStyle(.bordered)
        }
        .padding()
    }

    private func row(_ side: SpeedAnswer.Side, faster: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(side.name).font(.headline)
            if faster {
                Image(systemName: "hare.fill").foregroundStyle(.green)
                    .accessibilityLabel("Faster")
            }
            Spacer()
            Text("\(side.speed)").font(.title2.monospacedDigit().bold())
        }
    }
}

struct LegalitySnippetView: View {
    let answer: LegalityAnswer
    let pokemon: PokemonEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(answer.isLegal ? "Legal in \(answer.regulation)" : "Not legal in \(answer.regulation)")
                    .font(.headline)
            } icon: {
                Image(systemName: answer.isLegal ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .foregroundStyle(answer.isLegal ? .green : .red)
            }
            Text(answer.spoken).font(.subheadline)
            if let schedule = answer.schedule {
                Text(schedule).font(.caption).foregroundStyle(.secondary)
            }
            Button(intent: OpenPokemonIntent(target: pokemon)) { OpenInAppLabel() }
                .buttonStyle(.bordered)
        }
        .padding()
    }
}

struct SetSnippetView: View {
    let answer: SetAnswer
    let savedSet: SavedSetEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(answer.name).font(.headline)
                    Text(answer.pokemon).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                ForEach(answer.types, id: \.self) { TypeBadge(type: $0) }
            }
            let held = [answer.ability, answer.item, answer.nature.map { "\($0) nature" }].compactMap { $0 }
            if !held.isEmpty {
                Text(held.joined(separator: " · ")).font(.subheadline)
            }
            Text(answer.details).font(.caption).foregroundStyle(.secondary)
            if !answer.moves.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(answer.moves, id: \.self) { move in
                        Text(move).font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
            HStack {
                Button(intent: LoadSetInCalcIntent(savedSet: savedSet)) {
                    Label("Damage Calc", systemImage: "bolt.fill").frame(maxWidth: .infinity)
                }
                Button(intent: OpenSetIntent(target: savedSet)) { OpenInAppLabel() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

struct TeamSnippetView: View {
    let answer: TeamAnswer
    let team: SavedTeamEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(answer.name).font(.headline)
            if answer.members.isEmpty {
                Text("No Pokémon yet.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(Array(answer.members.enumerated()), id: \.offset) { _, member in
                HStack(spacing: 6) {
                    Text(member.name).font(.subheadline)
                    if let item = member.item {
                        Text(item).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ForEach(member.types, id: \.self) { TypeBadge(type: $0) }
                }
            }
            if let regulation = answer.regulation {
                if answer.problems.isEmpty {
                    Label("Legal in \(regulation)", systemImage: "checkmark.seal.fill")
                        .font(.caption).foregroundStyle(.green)
                }
                ForEach(Array(answer.problems.enumerated()), id: \.offset) { _, problem in
                    Label(problem, systemImage: "xmark.octagon.fill")
                        .font(.caption2).foregroundStyle(.red)
                }
                ForEach(Array(answer.warnings.enumerated()), id: \.offset) { _, warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            Button(intent: OpenTeamIntent(target: team)) { OpenInAppLabel() }
                .buttonStyle(.bordered)
        }
        .padding()
    }
}
