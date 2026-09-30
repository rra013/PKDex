//
//  AppCommands.swift
//  PKReference
//
//  The Mac app's menu commands: the View menu lists the tabs, the first nine
//  on ⌘1–⌘9, and Edit › Find… (⌘F) starts a search in the window's toolbar
//  search field. iOS has neither menu.
//

#if os(macOS)
import AppKit
import SwiftUI

extension FocusedValues {
    /// The focused window's selected tab, for the View menu's tab commands.
    @Entry var selectedTab: Binding<RootTab>?
}

struct AppCommands: Commands {
    @FocusedValue(\.selectedTab) private var selectedTab
    @AppStorage(AppSettings.tabOrder) private var tabOrderRaw: String
    @AppStorage(AppSettings.hiddenTabs) private var hiddenTabsRaw: String

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()
            let tabs = TabLayout(orderRaw: tabOrderRaw, hiddenRaw: hiddenTabsRaw).visible
            ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                Button(tab.label) { selectedTab?.wrappedValue = .tab(tab) }
                    .keyboardShortcut(index < 9
                        ? KeyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                        : nil)
                    .disabled(selectedTab == nil)
            }
        }
        CommandGroup(after: .textEditing) {
            Button("Find…") {
                // `.searchable` puts AppKit's own search field in the toolbar;
                // any tab with search has one, so this covers them all.
                let search = NSApp.keyWindow?.toolbar?.items.lazy
                    .compactMap { $0 as? NSSearchToolbarItem }.first
                if let search {
                    search.beginSearchInteraction()
                } else {
                    NSSound.beep()
                }
            }
            .keyboardShortcut("f")
        }
    }
}
#endif
