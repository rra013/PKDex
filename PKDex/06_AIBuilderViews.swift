//
//  AIBuilderViews.swift
//  PKReference
//
//  UI for the on-device AI set builder. Three views:
//
//    AIBuilderButton          — small button you drop into SetBuilder /
//                               TeamBuilder sheets to open the generator
//    AIBuilderSheet           — sheet with prompt input, generation,
//                               result preview, "Use this set" action
//    AIModelDownloadView      — Settings section for downloading /
//                               deleting the model
//
//  All views are guarded against the model not being downloaded — if the
//  user taps the button without the model installed, they get pointed at
//  Settings rather than a confusing error.
//

import SwiftUI

// MARK: - Reusable button

/// Discriminated output of an AI builder run — either a single set or a full
/// team. The button's `mode` determines which case the callback will receive.
public enum AIBuilderOutput {
    case set(PokemonSet)
    case team(name: String?, strategy: String?, members: [PokemonSet])
}

/// Drop this anywhere a "generate with AI" entry point makes sense. It's
/// styled to match PKReference's existing card buttons.
public struct AIBuilderButton: View {
    public enum Mode {
        case singleSet
        case fullTeam
    }

    let mode: Mode
    let onCompletion: (Result<AIBuilderOutput, Error>) -> Void

    @State private var showingSheet = false
    @State private var showingDownloadPrompt = false
    @ObservedObject private var engine = PokiiInferenceEngine.shared

    public init(mode: Mode,
                onCompletion: @escaping (Result<AIBuilderOutput, Error>) -> Void) {
        self.mode = mode
        self.onCompletion = onCompletion
    }

    public var body: some View {
        Button {
            engine.refreshDownloadState()
            switch engine.state {
            case .notDownloaded, .downloading:
                showingDownloadPrompt = true
            default:
                showingSheet = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text(mode == .singleSet ? "AI Generate Set" : "AI Generate Team")
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(.white)
            .background(
                LinearGradient(colors: [.purple, .pink],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing),
                in: Capsule()
            )
        }
        .sheet(isPresented: $showingSheet) {
            AIBuilderSheet(mode: mode, onCompletion: { result in
                onCompletion(result)
                showingSheet = false
            })
        }
        .alert("Download AI model?", isPresented: $showingDownloadPrompt) {
            Button("Go to Settings") {
                // The user can navigate manually; we just dismiss. A
                // deeper integration could push the Settings tab.
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The AI set builder needs a one-time ~4.5 GB download. " +
                 "You can manage it in Settings → AI Builder.")
        }
    }
}

// MARK: - Generation sheet

public struct AIBuilderSheet: View {
    let mode: AIBuilderButton.Mode
    let onCompletion: (Result<AIBuilderOutput, Error>) -> Void

    @State private var prompt = ""
    @State private var isGenerating = false
    @State private var attemptCount = 0
    @State private var generatedResult: PokiiInferenceEngine.GenerationResult?
    @State private var generatedTeamResult: PokiiInferenceEngine.TeamGenerationResult?
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var engine = PokiiInferenceEngine.shared

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    promptCard
                    if isGenerating {
                        generatingCard
                    } else if let result = generatedResult {
                        resultCard(result: result)
                    } else if let teamResult = generatedTeamResult {
                        teamResultCard(result: teamResult)
                    } else if let err = errorMessage {
                        errorCard(message: err)
                    }
                    examplesCard
                }
                .padding()
            }
            .navigationTitle(mode == .singleSet ? "AI Set Builder" : "AI Team Builder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isGenerating)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Cards

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Describe your Pokemon", systemImage: "text.bubble")
                .font(.headline)
            TextEditor(text: $prompt)
                .frame(minHeight: 80)
                .padding(8)
                .background(Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 8))
                .font(.body)
                .disabled(isGenerating)
                .overlay(alignment: .topLeading) {
                    if prompt.isEmpty {
                        Text("e.g. bulky Gardevoir, scarf Garchomp, " +
                             "rain Pelipper")
                            .foregroundStyle(.tertiary)
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }
            HStack {
                Spacer()
                Button {
                    runGeneration()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("Generate")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .foregroundStyle(.white)
                    .background(
                        prompt.trimmingCharacters(in: .whitespaces).isEmpty
                            ? AnyShapeStyle(Color.gray)
                            : AnyShapeStyle(LinearGradient(
                                colors: [.purple, .pink],
                                startPoint: .leading, endPoint: .trailing)),
                        in: Capsule()
                    )
                }
                .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty
                          || isGenerating)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    private var generatingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(attemptCount > 1
                 ? "Refining (attempt \(attemptCount))…"
                 : "Generating…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }

    private func resultCard(result: PokiiInferenceEngine.GenerationResult) -> some View {
        let set = result.set
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Result", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Spacer()
            }
            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(set.species).font(.title3.bold())
                    Spacer()
                    if let item = set.item {
                        Text(item)
                            .font(.caption)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.fill.tertiary, in: Capsule())
                    }
                }
                HStack(spacing: 12) {
                    Text(set.ability)
                        .font(.caption).foregroundStyle(.orange)
                    Text(set.nature)
                        .font(.caption).foregroundStyle(.secondary)
                    if let tera = set.teraType, !tera.isEmpty {
                        Text("Tera: \(tera)")
                            .font(.caption2)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(.fill.tertiary, in: Capsule())
                    }
                }
            }

            // Moves
            FlowLayout(spacing: 4) {
                ForEach(set.moves, id: \.self) { move in
                    Text(move)
                        .font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.fill.quaternary, in: Capsule())
                }
            }

            // Stat points readout
            let sp = set.statPoints
            HStack(spacing: 8) {
                statChip("HP", sp.hp)
                statChip("Atk", sp.atk)
                statChip("Def", sp.def)
                statChip("SpA", sp.spa)
                statChip("SpD", sp.spd)
                statChip("Spe", sp.spe)
            }
            .font(.caption2)
            Text("Total: \(set.statPointTotal) / 66")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            // Info banners — clip message (if we trimmed) and/or budget
            // note (if user has unspent SP). Both are user-actionable
            // context; neither is a hard error.
            if let clip = result.clipMessage {
                infoBanner(systemImage: "scissors", text: clip,
                           tint: .orange)
            }
            if let budget = result.budgetNote {
                infoBanner(systemImage: "plus.circle", text: budget,
                           tint: .blue)
            }

            Divider()
            HStack {
                Button {
                    runGeneration()  // retry
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button {
                    onCompletion(.success(.set(set)))
                } label: {
                    Label("Use this set", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }

    private func teamResultCard(result: PokiiInferenceEngine.TeamGenerationResult)
        -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Team", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Spacer()
                Text("\(result.members.count) of 6")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let name = result.teamName, !name.isEmpty {
                Text(name).font(.title3.bold())
            }
            if let strat = result.strategy, !strat.isEmpty {
                Text(strat)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(spacing: 8) {
                ForEach(Array(result.members.enumerated()), id: \.offset) { idx, member in
                    teamMemberRow(index: idx + 1, member: member)
                }
            }

            if !result.unresolvedViolations.isEmpty {
                infoBanner(
                    systemImage: "exclamationmark.triangle",
                    text: "\(result.unresolvedViolations.count) unresolved " +
                          "violation(s). You can still use this team and " +
                          "edit individual slots afterwards.",
                    tint: .orange
                )
            }

            Divider()
            HStack {
                Button {
                    runGeneration()
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button {
                    onCompletion(.success(.team(
                        name: result.teamName,
                        strategy: result.strategy,
                        members: result.members
                    )))
                } label: {
                    Label("Use this team", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(result.members.isEmpty)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }

    private func teamMemberRow(index: Int, member: PokemonSet) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("\(index).")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Text(member.species)
                    .font(.subheadline.bold())
                Spacer()
                if let item = member.item, !item.isEmpty {
                    Text(item)
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.fill.tertiary, in: Capsule())
                }
            }
            HStack(spacing: 8) {
                Text(member.ability)
                    .font(.caption2).foregroundStyle(.orange)
                if let role = member.role, !role.isEmpty {
                    Text(role)
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Text(member.moves.joined(separator: " / "))
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    /// Compact tinted banner used for clip and budget info under the
    /// result card. Keeps copy short — these are passive info, not
    /// errors, so they shouldn't dominate the layout.
    private func infoBanner(systemImage: String, text: String,
                            tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .font(.caption)
                .padding(.top, 1)
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func errorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Generation failed", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Try Again") { runGeneration() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color.red.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 14))
    }

    private var examplesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Examples", systemImage: "lightbulb")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(["bulky Gardevoir",
                     "Garchomp without Trick Room",
                     "scarf Charizard",
                     "Pelipper for rain"], id: \.self) { example in
                Button {
                    prompt = example
                } label: {
                    HStack {
                        Text(example)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func statChip(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 1) {
            Text(label).foregroundStyle(.secondary)
            Text("\(value)").bold()
                .foregroundStyle(value >= 28 ? .green : .primary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Action

    private func runGeneration() {
        let userPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userPrompt.isEmpty else { return }

        isGenerating = true
        attemptCount = 0
        generatedResult = nil
        generatedTeamResult = nil
        errorMessage = nil

        Task {
            do {
                // Make sure model is loaded
                try await engine.load()
                switch mode {
                case .singleSet:
                    let result = try await engine.generateSet(
                        userPrompt: userPrompt
                    ) { attempt, _ in
                        Task { @MainActor in
                            attemptCount = attempt
                        }
                    }
                    await MainActor.run {
                        generatedResult = result
                        isGenerating = false
                    }
                case .fullTeam:
                    let result = try await engine.generateTeam(
                        userPrompt: userPrompt
                    ) { attempt, _ in
                        Task { @MainActor in
                            attemptCount = attempt
                        }
                    }
                    await MainActor.run {
                        generatedTeamResult = result
                        isGenerating = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }
}

// MARK: - Settings: download UI

public struct AIModelDownloadView: View {
    @ObservedObject private var downloader = PokiiModelDownloader.shared
    @ObservedObject private var engine = PokiiInferenceEngine.shared
    @State private var allowCellular = false

    public init() {}

    public var body: some View {
        Section {
            switch downloader.status {
            case .idle:
                if engine.state == .downloaded || engine.state == .ready {
                    installedView
                } else {
                    notInstalledView
                }
            case .fetchingManifest:
                statusRow(text: "Preparing download…", showSpinner: true)
            case .downloading(let file, let idx, let total):
                downloadingView(file: file, idx: idx, total: total)
            case .verifying(let file):
                statusRow(text: "Verifying \(file)…", showSpinner: true)
            case .completed:
                installedView
            case .cancelled:
                cancelledView
            case .failed(let err):
                failedView(err: err)
            }
        } header: {
            Label("AI Set Builder", systemImage: "sparkles")
        } footer: {
            Text("On-device AI uses ~4.5 GB of storage and runs entirely on " +
                 "your iPhone — no data leaves your device.")
        }
    }

    // MARK: Subviews

    private var notInstalledView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Not Installed")
                .font(.subheadline.bold())
            Text("Download enables the AI buttons in Sets and Teams. " +
                 "~4.5 GB, one-time download.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Allow cellular download", isOn: $allowCellular)
                .font(.caption)
            Button {
                downloader.startDownload(
                    version: PokiiInferenceEngine.modelVersion,
                    allowCellular: allowCellular
                )
            } label: {
                Label("Download AI Model", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        }
        .padding(.vertical, 4)
    }

    private func downloadingView(file: String, idx: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Downloading \(idx + 1) of \(total)")
                    .font(.subheadline.bold())
                Spacer()
                Button("Cancel") {
                    downloader.cancelDownload()
                }
                .font(.caption)
                .foregroundStyle(.red)
            }
            ProgressView(value: downloader.progress.fraction)
                .tint(.purple)
            HStack {
                Text(file).font(.caption2.monospaced())
                    .foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text(formatBytes(downloader.progress.bytesDownloaded) +
                     " / " + formatBytes(downloader.progress.bytesTotal))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusRow(text: String, showSpinner: Bool) -> some View {
        HStack {
            if showSpinner { ProgressView().controlSize(.small) }
            Text(text).font(.subheadline)
            Spacer()
        }
    }

    private var installedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Installed").font(.subheadline.bold())
                Spacer()
                Text(formatBytes(downloader.diskUsage(
                    version: PokiiInferenceEngine.modelVersion)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text("AI Set Builder is ready. Look for the ✨ button in " +
                 "Sets and Teams.")
                .font(.caption).foregroundStyle(.secondary)
            Button(role: .destructive) {
                try? downloader.deleteModel(
                    version: PokiiInferenceEngine.modelVersion)
                engine.unload()
                engine.refreshDownloadState()
            } label: {
                Label("Delete Model", systemImage: "trash")
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private var cancelledView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Download cancelled")
                .font(.subheadline.bold())
                .foregroundStyle(.orange)
            Button("Resume Download") {
                downloader.startDownload(
                    version: PokiiInferenceEngine.modelVersion,
                    allowCellular: allowCellular
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        }
        .padding(.vertical, 4)
    }

    private func failedView(err: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Download Failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.subheadline.bold())
            Text(err).font(.caption2).foregroundStyle(.secondary)
            Button("Retry") {
                downloader.startDownload(
                    version: PokiiInferenceEngine.modelVersion,
                    allowCellular: allowCellular
                )
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
