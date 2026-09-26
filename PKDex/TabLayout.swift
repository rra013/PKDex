//
//  TabLayout.swift
//  PKDex
//
//  The user's tab arrangement: every tab in their chosen order, plus the
//  ones they've hidden.
//
//  Order and visibility are stored separately. A hidden tab keeps its
//  place, so showing it again puts it back where it was. And a tab missing
//  from the stored order can only be one added in an update, so it's shown
//  at the end. The retired format, one list of visible tabs, couldn't tell
//  a hidden tab from a new one, and re-added every hidden tab on the next
//  launch.
//

import SwiftUI

struct TabLayout: Equatable {
    static let orderKey = "tabOrder"
    static let hiddenKey = "hiddenTabs"
    /// The retired format: the visible tabs, in order. Converted once, at
    /// launch, by `migrateLegacyStorage(in:)`.
    static let legacyEnabledKey = "enabledTabs"

    /// A compact-width (iPhone) tab bar holds this many items. With more,
    /// it shows one fewer and puts the rest under a More tab.
    static let compactBarCapacity = 5

    /// Every user tab, in display order. Settings isn't included: it always
    /// comes last and can't be hidden.
    private(set) var order: [AppTab]
    private(set) var hidden: Set<AppTab>

    init(order: [AppTab] = AppTab.allUserTabs, hidden: Set<AppTab> = []) {
        // Drop duplicates and non-user tabs, then add any tab the stored
        // order predates.
        var seen = Set<AppTab>()
        var cleaned = order.filter { AppTab.allUserTabs.contains($0) && seen.insert($0).inserted }
        cleaned += AppTab.allUserTabs.filter { !seen.contains($0) }
        self.order = cleaned
        self.hidden = hidden.intersection(AppTab.allUserTabs)
    }

    init(orderRaw: String, hiddenRaw: String) {
        self.init(order: Self.parse(orderRaw), hidden: Set(Self.parse(hiddenRaw)))
    }

    var orderRaw: String { Self.serialize(order) }
    /// Hidden tabs in display order, so the stored string is stable.
    var hiddenRaw: String { Self.serialize(order.filter(hidden.contains)) }

    /// The tabs to show, in order. Never empty: if every tab were hidden,
    /// which `setHidden` doesn't allow, all of them are shown.
    var visible: [AppTab] {
        let shown = order.filter { !hidden.contains($0) }
        return shown.isEmpty ? order : shown
    }

    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
    }

    /// False only for the last visible tab.
    func canHide(_ tab: AppTab) -> Bool { visible != [tab] }

    mutating func setHidden(_ tab: AppTab, _ isHidden: Bool) {
        if isHidden {
            guard canHide(tab) else { return }
            hidden.insert(tab)
        } else {
            hidden.remove(tab)
        }
    }

    /// The tab `raw` names if it's visible, otherwise the first visible
    /// tab, so hiding the default tab can't leave the app opening to one
    /// that isn't there.
    func launchTab(for raw: String) -> AppTab {
        if let tab = AppTab(rawValue: raw), visible.contains(tab) { return tab }
        return visible[0]
    }

    enum Placement: Equatable { case tabBar, more, hidden }

    /// Where `tab` lands in a compact-width tab bar, counting Settings.
    func compactPlacement(of tab: AppTab) -> Placement {
        guard let index = visible.firstIndex(of: tab) else { return .hidden }
        let fitsInBar = visible.count + 1 <= Self.compactBarCapacity
        return fitsInBar || index < Self.compactBarCapacity - 1 ? .tabBar : .more
    }

    /// Converts the retired `enabledTabs` list, keeping its order and
    /// treating tabs it didn't list as hidden. Runs before any view reads
    /// the layout, so the first frame already uses it; does nothing once
    /// converted.
    static func migrateLegacyStorage(in defaults: UserDefaults = .standard) {
        guard defaults.string(forKey: orderKey) == nil,
              let legacy = defaults.string(forKey: legacyEnabledKey) else { return }
        let enabled = parse(legacy)
        // The old code showed every tab when the list was empty or unreadable.
        let hidden = enabled.isEmpty ? [] : Set(AppTab.allUserTabs).subtracting(enabled)
        let layout = TabLayout(order: enabled, hidden: hidden)
        defaults.set(layout.orderRaw, forKey: orderKey)
        defaults.set(layout.hiddenRaw, forKey: hiddenKey)
        defaults.removeObject(forKey: legacyEnabledKey)
    }

    private static func parse(_ raw: String) -> [AppTab] {
        raw.split(separator: ",").compactMap { AppTab(rawValue: String($0)) }
    }

    private static func serialize(_ tabs: [AppTab]) -> String {
        tabs.map(\.rawValue).joined(separator: ",")
    }
}
