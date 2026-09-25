//
//  TeamSearchModel.swift
//  PKDex
//
//  State behind the Team Search tab. It loads the regulation's vocabulary
//  and tournament corpus, indexes the corpus, parses what the user types,
//  and runs the search. Cached teams show at once; a refresh then runs in
//  the background. The slow parts (JSON loading, indexing) run off the main
//  actor. Parsing and searching take a few milliseconds.
//
//  The parsed query shows as chips the user can edit: remove one, or flip
//  it between "include" and "exclude". Edits apply until the text changes
//  and is parsed again.
//

import Foundation
import Observation

@MainActor @Observable
final class TeamSearchModel {

    enum Status: Equatable {
        case idle
        /// First load, with nothing cached to show yet.
        case loading(completed: Int, total: Int)
        case ready
        case failed(String)
    }

    /// One thing the parser understood, or didn't, shown as a chip.
    enum Chip: Identifiable, Equatable {
        case species(SpeciesTerm, excluded: Bool)
        case move(MoveTerm, excluded: Bool)
        case style(TeamArchetype, excluded: Bool)
        case correction(TeamQuery.Correction)
        case unrecognized(String)

        var id: String {
            switch self {
            case .species(let term, let excluded): return "species|\(excluded)|\(term.displayName)"
            case .move(let term, let excluded): return "move|\(excluded)|\(term.id)"
            case .style(let style, let excluded): return "style|\(excluded)|\(style.id)"
            case .correction(let correction): return "correction|\(correction.typed)"
            case .unrecognized(let word): return "unrecognized|\(word)"
            }
        }

        var label: String {
            switch self {
            case .species(let term, let excluded): return (excluded ? "No " : "") + term.displayName
            case .move(let term, let excluded): return (excluded ? "No " : "") + term.name
            case .style(let style, let excluded): return (excluded ? "No " : "") + style.label
            case .correction(let correction): return "\(correction.typed) → \(correction.interpreted)"
            case .unrecognized(let word): return word
            }
        }

        var isExcluded: Bool {
            switch self {
            case .species(_, let excluded), .move(_, let excluded), .style(_, let excluded):
                return excluded
            case .correction, .unrecognized:
                return false
            }
        }

        /// Species, moves and styles can flip between include and exclude.
        var canInvert: Bool {
            switch self {
            case .species, .move, .style: return true
            case .correction, .unrecognized: return false
            }
        }
    }

    var regulation: ChampionsRegulation
    private(set) var status: Status = .idle
    /// A background refresh is running while cached results show.
    private(set) var isRefreshing = false
    /// Why the last refresh failed, when cached results are still showing.
    private(set) var refreshError: String?
    private(set) var query = TeamQuery()
    private(set) var results: [TeamComposition] = []
    private(set) var teamCount = 0
    private(set) var eventCount = 0
    private(set) var missingEventCount = 0
    /// When the tournament list was last fetched.
    private(set) var updatedAt: Date?

    private let store: TeamCorpusStore
    private let loadVocabulary: @Sendable (ChampionsRegulation) throws -> TeamSearchVocabulary
    private let now: () -> Date
    private var loadedRegulation: ChampionsRegulation?
    private var parser: TeamQueryParser?
    private var index: TeamSearchIndex?
    private var text = ""

    init(regulation: ChampionsRegulation = .current,
         store: TeamCorpusStore = .shared,
         loadVocabulary: @escaping @Sendable (ChampionsRegulation) throws -> TeamSearchVocabulary = {
             try TeamSearchVocabulary.bundled(for: $0)
         },
         now: @escaping () -> Date = Date.init) {
        self.regulation = regulation
        self.store = store
        self.loadVocabulary = loadVocabulary
        self.now = now
    }

    // MARK: Loading

    /// Loads the corpus for `regulation`: first from cache, then from
    /// Limitless. After a change of regulation, it starts over.
    func load(forceRefresh: Bool = false) async {
        let regulation = self.regulation
        if loadedRegulation != regulation {
            loadedRegulation = regulation
            parser = nil
            index = nil
            results = []
            status = .idle
            let loader = loadVocabulary
            do {
                let vocabulary = try await Task.detached { try loader(regulation) }.value
                guard self.regulation == regulation else { return }
                parser = TeamQueryParser(vocabulary: vocabulary)
                query = parser?.parse(text) ?? TeamQuery()
            } catch {
                loadedRegulation = nil
                status = .failed("This regulation's data couldn't be loaded.")
                return
            }
            if let cached = await store.cachedCorpus(format: regulation.limitlessFormat),
               !cached.teams.isEmpty {
                await apply(cached, for: regulation)
            }
        }
        guard !Task.isCancelled, self.regulation == regulation else { return }
        // Coming back to the tab shouldn't re-read and re-index the cache
        // while the list is still fresh.
        if !forceRefresh, index != nil, let updatedAt,
           now().timeIntervalSince(updatedAt) < TeamCorpusConfiguration().listTTL {
            return
        }

        if index == nil { status = .loading(completed: 0, total: 0) } else { isRefreshing = true }
        defer { isRefreshing = false }
        do {
            let corpus = try await store.corpus(for: regulation, forceRefresh: forceRefresh) {
                [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self, case .loading = self.status, self.regulation == regulation else { return }
                    self.status = .loading(completed: progress.completed, total: progress.total)
                }
            }
            await apply(corpus, for: regulation)
            refreshError = corpus.listRefreshError
        } catch {
            guard self.regulation == regulation else { return }
            if index == nil {
                status = .failed(error.localizedDescription)
            } else {
                refreshError = error.localizedDescription
            }
        }
    }

    private func apply(_ corpus: TeamCorpus, for regulation: ChampionsRegulation) async {
        guard let vocabulary = parser?.vocabulary else { return }
        let index = await Task.detached { TeamSearchIndex(corpus: corpus, vocabulary: vocabulary) }.value
        guard self.regulation == regulation else { return }
        self.index = index
        teamCount = corpus.teams.count
        eventCount = corpus.events.count
        missingEventCount = corpus.missingEvents.count
        updatedAt = corpus.listFetchedAt
        status = .ready
        search()
    }

    // MARK: Query

    /// Parses `text` and searches. Chip edits are dropped.
    func setText(_ text: String) {
        self.text = text
        query = parser?.parse(text) ?? TeamQuery()
        search()
    }

    var chips: [Chip] {
        var chips: [Chip] = []
        chips += query.species.map { .species($0, excluded: false) }
        chips += query.archetypes.map { .style($0, excluded: false) }
        chips += query.moves.map { .move($0, excluded: false) }
        chips += query.excludedSpecies.map { .species($0, excluded: true) }
        chips += query.excludedArchetypes.map { .style($0, excluded: true) }
        chips += query.excludedMoves.map { .move($0, excluded: true) }
        chips += query.corrections.map { .correction($0) }
        chips += query.unrecognized.map { .unrecognized($0) }
        return chips
    }

    func remove(_ chip: Chip) {
        switch chip {
        case .species(let term, _):
            query.species.removeAll { $0 == term }
            query.excludedSpecies.removeAll { $0 == term }
        case .move(let term, _):
            query.moves.removeAll { $0 == term }
            query.excludedMoves.removeAll { $0 == term }
        case .style(let style, _):
            query.archetypes.removeAll { $0 == style }
            query.excludedArchetypes.removeAll { $0 == style }
        case .correction(let correction):
            query.corrections.removeAll { $0 == correction }
        case .unrecognized(let word):
            query.unrecognized.removeAll { $0 == word }
        }
        search()
    }

    /// Flips a species, move or style between include and exclude.
    func invert(_ chip: Chip) {
        switch chip {
        case .species(let term, let excluded):
            remove(chip)
            if excluded { query.species.append(term) } else { query.excludedSpecies.append(term) }
        case .move(let term, let excluded):
            remove(chip)
            if excluded { query.moves.append(term) } else { query.excludedMoves.append(term) }
        case .style(let style, let excluded):
            remove(chip)
            if excluded { query.archetypes.append(style) } else { query.excludedArchetypes.append(style) }
        case .correction, .unrecognized:
            return
        }
        search()
    }

    private func search() {
        guard let index else {
            results = []
            return
        }
        results = TeamSearchEngine.search(query, in: index, now: now())
    }
}
