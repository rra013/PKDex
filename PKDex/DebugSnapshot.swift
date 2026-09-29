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
//            [-debugSnapshotDelay 4] [-debugWindowSize 1280x800] [-debugSnapshotQuit YES]
//
//  Pictures go to Library/Caches/Snapshots in the app's container
//  (~/Library/Containers/yukisoft.PKReference/Data/), named for the
//  argument or the time. Web views draw in another process, so they come
//  out blank.
//

#if DEBUG && os(macOS)
import AppKit
import SwiftUI

enum DebugSnapshot {
    static var folder: URL {
        URL.cachesDirectory.appending(path: "Snapshots", directoryHint: .isDirectory)
    }

    private static var mainWindow: NSWindow? {
        NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
    }

    /// Saves the main window, title bar and toolbar included, as
    /// `name`.png. Returns where, or nil if there's no window.
    @discardableResult
    static func save(named name: String? = nil) -> URL? {
        guard let window = mainWindow,
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("[DebugSnapshot] no window to save")
            return nil
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        let name = name ?? "snapshot-" + Date.now.formatted(.iso8601.time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
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

    /// The launch arguments' snapshot, if there is one: sizes the window,
    /// waits for the screen to settle, saves, and quits if asked.
    static func runFromLaunchArguments() async {
        let defaults = UserDefaults.standard
        guard let name = defaults.string(forKey: "debugSnapshot") else { return }
        if let size = defaults.string(forKey: "debugWindowSize")?.split(separator: "x").compactMap({ Double($0) }),
           size.count == 2 {
            mainWindow?.setContentSize(NSSize(width: size[0], height: size[1]))
        }
        let delay = defaults.double(forKey: "debugSnapshotDelay")
        try? await Task.sleep(for: .seconds(delay > 0 ? delay : 4))
        save(named: name)
        if defaults.bool(forKey: "debugSnapshotQuit") {
            NSApp.terminate(nil)
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
