//
//  DebugSnapshot.swift
//  PKReference
//
//  Debug Mac builds save pictures of their own window, so screens can be
//  checked without Screen Recording permission: the app draws its window
//  into an image itself, and nothing else on the screen is captured.
//  Release builds and iOS leave this out.
//
//  Two ways in:
//  - Debug › Save Window Snapshot (⇧⌘S), for a screen reached by hand.
//  - Launch arguments, for a scripted check. Settings can be passed the same
//    way, for that run only (`-defaultTab damageCalc -appAppearance dark`):
//
//        open -g -n -W "PK Reference.app" --args -debugSnapshot calc \
//            [-debugSnapshotDelay 4] [-debugWindowSize 1280x800] \
//            [-debugOpenSettings YES] [-debugOpenFirst YES] [-debugOpenSheet load] \
//            [-debugSnapshotStdout YES] [-debugSnapshotQuit YES]
//
//  `-debugOpenFirst YES` opens the first item of a list/detail tab (Mon
//  Index, Sets, Teams, Team Search), so its detail screen can be checked,
//  and `-debugOpenSheet` opens a sheet by the name its presenter gives.
//
//  Pictures go to Library/Caches/Snapshots in the app's container
//  (~/Library/Containers/yukisoft.PKReference/Data/), named for the
//  argument or the time. A launch-argument snapshot saves every open
//  window: the main one as `calc.png`, others with their title added
//  (`calc-Settings.png`, or `calc-sheet.png` for an untitled sheet).
//  macOS asks before another app reads the container, so with
//  `-debugSnapshotStdout YES` each picture is also printed, as a
//  `[DebugSnapshot png <name>] <base64>` line, for whoever launched the
//  app to decode. Glass, such as the sidebar and search fields, comes out
//  blank, and so do web views, which draw in another process.
//

#if DEBUG && os(macOS)
import AppKit
import SwiftUI

enum DebugSnapshot {
    static var folder: URL {
        URL.cachesDirectory.appending(path: "Snapshots", directoryHint: .isDirectory)
    }

    /// With `-debugOpenFirst YES`, a list/detail tab calls this from a task
    /// on its split view, and it runs `open` a second later. Selecting
    /// before the split view has appeared lays it out billions of points
    /// wide, and the window saves that as its divider position, so it waits
    /// as a click would.
    static func openFirstItem(_ open: () -> Void) async {
        guard UserDefaults.standard.bool(forKey: "debugOpenFirst") else { return }
        try? await Task.sleep(for: .seconds(1))
        open()
    }

    /// With `-debugSnippets YES`, renders the App Intents' snippets, which
    /// only Siri and Spotlight show, with the store's data: Garchomp's
    /// lookup, its Earthquake on Heatran with no investment, and Team Search
    /// for "Trick Room". Saved like the windows, as `<name>-snippet-lookup`
    /// and so on.
    static func renderSnippets(named name: String) async {
        var snippets: [(String, AnyView)] = []
        if let pokemon = try? IntentData.pokemonEntities(ids: [445]).first,
           let answer = try? IntentData.lookup(445) {
            snippets.append(("lookup", AnyView(PokemonSnippetView(answer: answer, pokemon: pokemon))))
        }
        if let attacker = try? IntentData.pokemonEntities(ids: [445]).first,
           let defender = try? IntentData.pokemonEntities(ids: [485]).first,
           let move = try? IntentData.moveEntities(ids: [89]).first {
            let open = OpenCalcIntent(attacker: attacker, move: move, defender: defender,
                                      attackerStats: .noInvestment, defenderStats: .noInvestment)
            if let request = try? open.request, let answer = try? IntentData.damage(request) {
                snippets.append(("damage", AnyView(DamageSnippetView(answer: answer, open: open))))
            }
        }
        if let answer = try? await IntentData.teamSearch("Trick Room") {
            snippets.append(("teams", AnyView(TeamSearchSnippetView(answer: answer))))
        }
        for (kind, view) in snippets {
            let renderer = ImageRenderer(content: view.frame(width: 380).background(.background))
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                print("[DebugSnapshot] couldn't render the \(kind) snippet")
                continue
            }
            print("[DebugSnapshot png \(name)-snippet-\(kind)] \(png.base64EncodedString())")
            fflush(stdout)
        }
    }

    /// Prints the menu bar, one item a line with its shortcut, since a
    /// snapshot can't show menus: `-debugMenus YES`.
    static func printMenus() {
        func describe(_ item: NSMenuItem) -> String {
            guard !item.isSeparatorItem else { return "—" }
            var line = item.title
            if !item.keyEquivalent.isEmpty {
                let mods = item.keyEquivalentModifierMask
                let symbols = [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
                line += "  " + symbols.filter { mods.contains($0.0) }.map(\.1).joined() + item.keyEquivalent.uppercased()
            }
            return line + (item.isEnabled ? "" : "  (disabled)")
        }
        func walk(_ menu: NSMenu, _ depth: Int) {
            for item in menu.items {
                print("[menu] " + String(repeating: "  ", count: depth) + describe(item))
                if let submenu = item.submenu, depth < 2 { walk(submenu, depth + 1) }
            }
        }
        if let main = NSApp.mainMenu { walk(main, 0) }
        fflush(stdout)
    }

    /// With `-debugOpenSheet <name>`, a view that presents the sheet
    /// `name` calls this from a task, and it runs `open` a second later.
    static func openSheet(_ name: String, _ open: () -> Void) async {
        guard UserDefaults.standard.string(forKey: "debugOpenSheet") == name else { return }
        try? await Task.sleep(for: .seconds(1))
        open()
    }

    private static var mainWindow: NSWindow? {
        NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
    }

    /// Saves the key window, or the main one, as a picture named for the
    /// local time, and plays a sound once it's saved.
    @discardableResult
    static func save() -> URL? {
        guard let window = NSApp.keyWindow ?? mainWindow else {
            print("[DebugSnapshot] no window to save")
            NSSound.beep()
            return nil
        }
        let name = "snapshot-" + Date.now.formatted(.verbatim(
            "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits).\(second: .twoDigits)",
            timeZone: .current, calendar: .current))
        let url = save(window, named: name)
        if url != nil {
            NSSound(named: "Pop")?.play()
        } else {
            NSSound.beep()
        }
        return url
    }

    /// Saves every open window: the main one as `name`, others with their
    /// title added, or "sheet" for an untitled sheet.
    static func saveAll(named name: String) {
        let main = mainWindow
        for window in NSApp.windows where window.isVisible && window.canBecomeKey {
            let title = window.title.isEmpty ? (window.isSheet ? "sheet" : "window") : window.title
            save(window, named: window === main ? name : "\(name)-\(title)")
        }
    }

    /// Saves `window`, title bar and toolbar included, as `name`.png.
    /// Returns where, or nil if it couldn't be drawn or written.
    @discardableResult
    private static func save(_ window: NSWindow, named name: String) -> URL? {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("[DebugSnapshot] couldn't draw \(name)")
            return nil
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        do {
            guard let png = rep.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            if UserDefaults.standard.bool(forKey: "debugSnapshotStdout") {
                print("[DebugSnapshot png \(name)] \(png.base64EncodedString())")
                fflush(stdout)
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: name + ".png")
            try png.write(to: url)
            print("[DebugSnapshot] saved \(url.path)")
            return url
        } catch {
            print("[DebugSnapshot] couldn't save \(name): \(error)")
            return nil
        }
    }

    /// Runs the launch arguments' snapshot, if there is one: sizes the
    /// window, opens Settings if asked, waits for the screen to settle,
    /// saves, and quits if asked.
    struct LaunchArguments: ViewModifier {
        @Environment(\.openSettings) private var openSettings

        func body(content: Content) -> some View {
            content.task {
                let defaults = UserDefaults.standard
                guard let name = defaults.string(forKey: "debugSnapshot") else { return }
                if let size = defaults.string(forKey: "debugWindowSize")?.split(separator: "x")
                    .compactMap({ Double($0) }), size.count == 2 {
                    mainWindow?.setContentSize(NSSize(width: size[0], height: size[1]))
                }
                if defaults.bool(forKey: "debugOpenSettings") {
                    openSettings()
                }
                let delay = defaults.double(forKey: "debugSnapshotDelay")
                try? await Task.sleep(for: .seconds(delay > 0 ? delay : 4))
                saveAll(named: name)
                if defaults.bool(forKey: "debugMenus") {
                    printMenus()
                }
                if defaults.bool(forKey: "debugSnippets") {
                    await renderSnippets(named: name)
                }
                if defaults.bool(forKey: "debugSnapshotQuit") {
                    // Not NSApp.terminate: a sheet with a text field open
                    // held that off, and the run never ended.
                    exit(0)
                }
            }
        }
    }

    struct Commands: SwiftUI.Commands {
        var body: some SwiftUI.Commands {
            CommandMenu("Debug") {
                Button("Save Window Snapshot") { DebugSnapshot.save() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
}
#endif
