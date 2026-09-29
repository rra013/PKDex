//
//  DebugSnapshot.swift
//  PKDex
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
//        open -g -n -W PKDex.app --args -debugSnapshot calc \
//            [-debugSnapshotDelay 4] [-debugWindowSize 1280x800] \
//            [-debugOpenSettings YES] [-debugOpenFirst YES] [-debugSnapshotQuit YES]
//
//  `-debugOpenFirst YES` opens the first item of a list/detail tab (Mon
//  Index, Sets, Teams, Team Search), so its detail screen can be checked.
//
//  Pictures go to Library/Caches/Snapshots in the app's container
//  (~/Library/Containers/yukisoft.PKReference/Data/), named for the
//  argument or the time. A launch-argument snapshot saves every open
//  window: the main one as `calc.png`, others with their title added
//  (`calc-Settings.png`). Glass, such as the sidebar and search fields,
//  comes out blank, and so do web views, which draw in another process.
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
    /// title added.
    static func saveAll(named name: String) {
        let main = mainWindow
        for window in NSApp.windows where window.isVisible && window.canBecomeKey {
            save(window, named: window === main ? name : "\(name)-\(window.title)")
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
                if defaults.bool(forKey: "debugSnapshotQuit") {
                    NSApp.terminate(nil)
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
