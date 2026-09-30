//
//  AppNavigator.swift
//  PKReference
//
//  Where an App Intent that opens the app wants it to go. The intent sets
//  `request`; the root view shows the request's tab, and that tab takes the
//  request and clears it. A request for a hidden tab is dropped.
//

import Foundation
import Observation

@Observable
final class AppNavigator {
    static let shared = AppNavigator()

    enum Request: Equatable {
        /// A Pokémon's page in the Mon Index, by National Dex number.
        case pokemon(speciesID: Int)
        /// The calc, with both sides loaded.
        case calc(CalcRequest)
        /// Team Search, with this query.
        case teamSearch(query: String)

        var tab: AppTab {
            switch self {
            case .pokemon: .monIndex
            case .calc: .damageCalc
            case .teamSearch: .teamSearch
            }
        }
    }

    var request: Request?

    #if DEBUG
    /// Debug builds: `-debugNavigate pokemon:445`, `-debugNavigate
    /// "teamSearch:Trick Room"` or `-debugNavigate calc:445,485,89`
    /// (attacker, defender and move ids, both with no investment) makes the
    /// same request an intent's Open button would, so opening the app can be
    /// checked without Siri.
    func requestFromLaunchArguments() {
        guard let argument = UserDefaults.standard.string(forKey: "debugNavigate"),
              let colon = argument.firstIndex(of: ":") else { return }
        let value = String(argument[argument.index(after: colon)...])
        switch argument[..<colon] {
        case "pokemon":
            if let id = Int(value) { request = .pokemon(speciesID: id) }
        case "teamSearch":
            request = .teamSearch(query: value)
        case "calc":
            let ids = value.split(separator: ",").compactMap { Int($0) }
            if ids.count == 3 {
                request = .calc(CalcRequest(attackerID: ids[0], attackerStats: .noInvestment,
                                            defenderID: ids[1], defenderStats: .noInvestment,
                                            moveID: ids[2]))
            }
        default:
            break
        }
    }
    #endif
}
