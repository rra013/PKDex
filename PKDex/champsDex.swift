//
//  champsDex.swift
//  PKDex
//
//  Compatibility shim. The `championsRoster` Set used to be hand-maintained
//  here (and again inside `PokeSyncManager`), which drifted relative to
//  `champions-m-a.json` — the symptom was the Mon Index showing Ursaluna but
//  not Scovillain. The single source of truth now lives in the bundled
//  regulation JSON via `ChampionsRegulation`; this file just keeps the
//  `championsRoster` identifier alive for existing callers.
//

import Foundation

/// Species names allowed in the currently-active Champions regulation.
/// Reads `champions-<id>.json` via `ChampionsRegulation.current` and is safe
/// to call from anywhere — the loader caches after the first decode.
var championsRoster: Set<String> {
    ChampionsRegulation.current.speciesWhitelist()
}
