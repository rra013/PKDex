//
//  AcknowledgementsTests.swift
//  PKDexTests
//
//  The licenses that PK Reference's open-source components require it to
//  carry have to be in the app bundle, not just the repository. The tests
//  run inside the app, so `Bundle.main` is the shipped bundle.
//

import Testing
import Foundation
@testable import PKDex

@MainActor
@Suite("Acknowledgements")
struct AcknowledgementsTests {

    @Test("Every open-source component names its license and bundles its text")
    func licensesAreBundled() {
        for item in Acknowledgement.code {
            #expect(item.license != nil, "\(item.name) has no license")
            #expect(!item.licenseFiles.isEmpty, "\(item.name) has no license file")
            for file in item.licenseFiles {
                let text = Acknowledgement.text(of: file)
                #expect(text?.isEmpty == false, "\(file) for \(item.name) isn't in the bundle")
            }
        }
    }

    @Test("PokéFinder's license is the full GPL-3.0 text")
    func pokeFinderIsGPL() throws {
        let pokeFinder = try #require(Acknowledgement.code.first { $0.name == "PokéFinder" })
        #expect(pokeFinder.license == "GPL-3.0")
        let text = try #require(Acknowledgement.text(of: "COPYING"))
        #expect(text.contains("GNU GENERAL PUBLIC LICENSE"))
        #expect(text.contains("Version 3, 29 June 2007"))
        #expect(text.contains("END OF TERMS AND CONDITIONS"))
    }

    @Test("Reflowing joins a paragraph's lines and keeps paragraph breaks")
    func reflow() {
        let text = "MIT License\r\n\r\nPermission is hereby granted,\n   free of charge,\nto any person.\n  \n\nTHE SOFTWARE\nIS PROVIDED \"AS IS\"\n"
        #expect(Acknowledgement.reflowed(text) == """
            MIT License

            Permission is hereby granted, free of charge, to any person.

            THE SOFTWARE IS PROVIDED "AS IS"
            """)
    }

    @Test("Data sources carry no license files")
    func dataSourcesHaveNoLicenseFiles() {
        #expect(Acknowledgement.dataSources.allSatisfy { $0.license == nil && $0.licenseFiles.isEmpty })
        #expect(Acknowledgement.dataSources.map(\.name) == ["PokeAPI", "Serebii.net", "Limitless"])
    }
}
