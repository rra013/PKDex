//
//  AcknowledgementsView.swift
//  PKDex
//
//  Settings → Acknowledgements & Licenses: the data sources the app reads,
//  and the open-source code it's built on, with each license's full text.
//
//  The license files are bundled from PKDex/Licenses, plus PKDex/Core/COPYING
//  for PokéFinder's GPL-3.0, so every build carries them, as the MIT, BSD,
//  Apache and GPL licenses require. THIRD_PARTY_NOTICES.md at the repository
//  root lists the same components.
//

import SwiftUI

struct Acknowledgement: Identifiable {
    let name: String
    /// Who made it.
    let credit: String
    /// What the app uses it for.
    let use: String
    let url: URL
    /// The license, for code. nil for data sources, which have terms of use
    /// instead.
    let license: String?
    /// Bundled license and notice files, shown in order.
    let licenseFiles: [String]

    var id: String { name }

    static let dataSources: [Acknowledgement] = [
        Acknowledgement(
            name: "PokeAPI", credit: "PokeAPI contributors",
            use: "Pokédex, stats, abilities, learnsets and moves",
            url: URL(string: "https://pokeapi.co")!, license: nil, licenseFiles: []),
        Acknowledgement(
            name: "Serebii.net", credit: "Serebii.net",
            use: "Pokédex, Attackdex and Abilitydex pages, and the Champions regulation data",
            url: URL(string: "https://www.serebii.net")!, license: nil, licenseFiles: []),
        Acknowledgement(
            name: "Limitless", credit: "Limitless TCG",
            use: "Tournaments, standings and team sheets, and Team Search's teams",
            url: URL(string: "https://play.limitlesstcg.com")!, license: nil, licenseFiles: []),
        Acknowledgement(
            name: "Smogon", credit: "Smogon University",
            use: "Ladder usage statistics, for Team Search's teammate suggestions",
            url: URL(string: "https://www.smogon.com/stats/")!, license: nil, licenseFiles: []),
    ]

    static let code: [Acknowledgement] = [
        Acknowledgement(
            name: "Smogon damage calculator (@smogon/calc)",
            credit: "Honko, Austin, Kris and the damage-calc contributors",
            use: "The Champions damage engine, ported to Swift, and its data",
            url: URL(string: "https://github.com/smogon/damage-calc")!,
            license: "MIT", licenseFiles: ["License-smogon-damage-calc.txt"]),
        Acknowledgement(
            name: "Pokémon Showdown", credit: "Guangcong Luo and contributors",
            use: "Reference for Champions mechanics and data",
            url: URL(string: "https://github.com/smogon/pokemon-showdown")!,
            license: "MIT", licenseFiles: ["License-pokemon-showdown.txt"]),
        Acknowledgement(
            name: "PokéFinder", credit: "Admiral_Fish, bumba and EzPzStreamz",
            use: "The RNG tools' generators, searchers and encounter data",
            url: URL(string: "https://github.com/Admiral-Fish/PokeFinder")!,
            license: "GPL-3.0", licenseFiles: ["COPYING"]),
        Acknowledgement(
            name: "EonTimer", credit: "DasAmpharos",
            use: "The RNG timer",
            url: URL(string: "https://github.com/DasAmpharos/EonTimer")!,
            license: "MIT", licenseFiles: ["License-EonTimer.txt"]),
        Acknowledgement(
            name: "JSON for Modern C++", credit: "Niels Lohmann",
            use: "JSON parsing in the RNG core",
            url: URL(string: "https://github.com/nlohmann/json")!,
            license: "MIT", licenseFiles: ["License-nlohmann-json.txt"]),
        Acknowledgement(
            name: "Flash Perfect Hash Table", credit: "renzibei",
            use: "Hash tables in the RNG core",
            url: URL(string: "https://github.com/renzibei/fph-table")!,
            license: "Apache-2.0",
            licenseFiles: ["Notice-fph-table.txt", "License-fph-table.txt"]),
        Acknowledgement(
            name: "Zstandard", credit: "Meta Platforms, Inc. and affiliates",
            use: "Decompressing the RNG core's resources",
            url: URL(string: "https://github.com/facebook/zstd")!,
            license: "BSD", licenseFiles: ["License-zstd.txt"]),
    ]

    /// A bundled license file's text, or nil when it isn't in the bundle.
    static func text(of file: String, in bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: file, withExtension: nil) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// License files are hard-wrapped at about 80 columns, which wraps
    /// raggedly on a phone. This joins each paragraph's lines so the text
    /// wraps to the screen. Blank lines still separate paragraphs.
    nonisolated static func reflowed(_ text: String) -> String {
        var paragraphs: [String] = []
        var current: [String] = []
        for line in text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if !current.isEmpty { paragraphs.append(current.joined(separator: " ")) }
                current = []
            } else {
                current.append(trimmed)
            }
        }
        if !current.isEmpty { paragraphs.append(current.joined(separator: " ")) }
        return paragraphs.joined(separator: "\n\n")
    }
}

struct AcknowledgementsView: View {
    var body: some View {
        List {
            Section {
                ForEach(Acknowledgement.dataSources) { item in
                    Link(destination: item.url) {
                        AcknowledgementRow(item: item)
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Text("Data")
            } footer: {
                Text("These sites aren't affiliated with PK Reference.")
            }

            Section {
                ForEach(Acknowledgement.code) { item in
                    NavigationLink {
                        LicenseTextView(item: item)
                    } label: {
                        AcknowledgementRow(item: item)
                    }
                }
            } header: {
                Text("Open-Source Code")
            } footer: {
                Text("Tap an entry for its full license. The RNG tools also build on research by the Pokémon RNG community, including RNG Reporter, PPRNG and 3DSRNG Tool.")
            }
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AcknowledgementRow: View {
    let item: Acknowledgement

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(item.name)
                    .font(.body.weight(.medium))
                if let license = item.license {
                    Text(license)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.fill.tertiary, in: Capsule())
                }
            }
            Text(item.credit)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(item.use)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct LicenseTextView: View {
    let item: Acknowledgement

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Link(item.url.absoluteString, destination: item.url)
                    .font(.footnote)
                ForEach(item.licenseFiles, id: \.self) { file in
                    Text(Acknowledgement.text(of: file).map(Acknowledgement.reflowed)
                         ?? "License text not found (\(file)).")
                        .font(.footnote)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
