//
//  MoreTab.swift
//  PKDex
//
//  The app's own More tab, used on iPhone, and in a narrow iPad window, when
//  there are more tabs than fit in the tab bar.
//
//  The system's More list wraps each overflow tab in a navigation bar of
//  its own. Every tab here brings its own NavigationStack as well, so tabs
//  opened from the system list showed two bars with two back buttons. This
//  More tab has one NavigationStack, and a tab opened from it joins that
//  stack instead of starting its own: `TabNavigationStack` checks
//  `isInMoreList` and leaves its NavigationStack out.
//
//  Going back from a tab to the More list closes it, so a tab with work in
//  progress reports it with `leaveWarning(_:)`, and back asks first.
//

import SwiftUI

/// What the root TabView has selected: a tab in the bar, or the More tab.
enum RootTab: Hashable {
    case tab(AppTab)
    case more
}

extension EnvironmentValues {
    /// True for a tab opened from the More list, which provides the
    /// navigation stack.
    @Entry var isInMoreList: Bool = false

    /// Set by the Arrange Tabs page while it's open. The tab bar waits for
    /// it to close before rearranging, so the page isn't rebuilt mid-edit.
    @Entry var isArrangingTabs: Binding<Bool> = .constant(false)
}

/// A tab's navigation root: a NavigationStack of its own, or none when the
/// tab is opened from the More list, whose stack it joins.
struct TabNavigationStack<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.isInMoreList) private var isInMoreList

    var body: some View {
        if isInMoreList {
            content
        } else {
            NavigationStack { content }
        }
    }
}

// MARK: - Leave Warnings

/// What a tab would lose if closed, such as a battle in progress. The first
/// non-nil message in the tab's views wins.
struct LeaveWarningKey: PreferenceKey {
    static let defaultValue: String? = nil
    static func reduce(value: inout String?, nextValue: () -> String?) {
        value = value ?? nextValue()
    }
}

extension View {
    /// Reports what closing this tab would lose, or nil when nothing. Only
    /// read under the More list: in the tab bar, switching tabs keeps them.
    func leaveWarning(_ message: String?) -> some View {
        preference(key: LeaveWarningKey.self, value: message)
    }
}

/// A tab opened from the More list. When the tab reports a leave warning,
/// its back button asks first; hiding the system back button also turns off
/// the edge swipe, which would otherwise close the tab without asking. The
/// warning and prompt state live in `MoreList`, which asks the same question
/// when the More tab is tapped again.
private struct MoreTabPage<Content: View>: View {
    let tab: AppTab
    @Binding var warning: String?
    @Binding var isAsking: Bool
    let leave: () -> Void
    @ViewBuilder var content: Content

    @AppStorage(AppSettings.warnBeforeLeavingTab) private var warnBeforeLeaving: Bool

    private var asksFirst: Bool { warnBeforeLeaving && warning != nil }

    var body: some View {
        content
            .onPreferenceChange(LeaveWarningKey.self) { warning = $0 }
            .navigationBarBackButtonHidden(asksFirst)
            .toolbar {
                if asksFirst {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            isAsking = true
                        } label: {
                            Image(systemName: "chevron.backward")
                        }
                        // The system back button is the label color, not the tint.
                        .tint(.primary)
                        .accessibilityLabel("Back")
                    }
                }
            }
            .alert("Leave \(tab.label)?", isPresented: $isAsking) {
                Button("Leave", role: .destructive, action: leave)
                Button("Leave & Don't Ask Again") {
                    warnBeforeLeaving = false
                    leave()
                }
                Button("Stay", role: .cancel) {}
            } message: {
                Text(warning ?? "")
            }
    }
}

// MARK: - More List

/// The More tab: a list of the tabs that don't fit in the bar. `path` is
/// its navigation, starting with the open tab if there is one; `openTab`
/// reports which tab that is, since a NavigationPath can't be read back.
struct MoreList<TabContent: View>: View {
    let tabs: [AppTab]
    @Binding var path: NavigationPath
    @Binding var openTab: AppTab?
    @ViewBuilder let tabContent: (AppTab) -> TabContent

    @AppStorage(AppSettings.warnBeforeLeavingTab) private var warnBeforeLeaving: Bool
    /// What the open tab would lose if closed.
    @State private var warning: String?
    @State private var isAskingToLeave = false

    /// Whether leaving the open tab should ask first.
    private var asksBeforeLeaving: Bool {
        warnBeforeLeaving && warning != nil && !path.isEmpty
    }

    var body: some View {
        NavigationStack(path: $path) {
            List(tabs) { tab in
                NavigationLink(value: tab) {
                    Label(tab.label, systemImage: tab.icon)
                }
            }
            .navigationTitle("More")
            .navigationDestination(for: AppTab.self) { tab in
                MoreTabPage(tab: tab, warning: $warning, isAsking: $isAskingToLeave,
                            leave: { path = NavigationPath() }) {
                    tabContent(tab)
                }
                .environment(\.isInMoreList, true)
                // A tab's wide layouts are split views, which can't be
                // pushed onto a stack; landscape iPhone gets its compact
                // layout here.
                .environment(\.horizontalSizeClass, .compact)
                .onAppear { openTab = tab }
            }
        }
        .onChange(of: path.isEmpty) { _, isEmpty in
            if isEmpty {
                openTab = nil
                warning = nil
            }
        }
        #if os(iOS)
        // Tapping the More tab again returns to the list, which the tab bar
        // does itself, without going through `path`.
        .background {
            TabReselectGuard(shouldHold: { asksBeforeLeaving },
                             onHeld: { isAskingToLeave = true })
        }
        #endif
    }
}

#if os(iOS)
// MARK: - Tab Reselect Guard

/// Holds back a tap on this view's tab while it's already selected, when
/// `shouldHold` says so, and calls `onHeld` instead. SwiftUI offers no hook
/// for that tap, so this finds the UITabBarController behind the TabView and
/// sits in front of its delegate, passing everything else through to it.
private struct TabReselectGuard: UIViewRepresentable {
    let shouldHold: () -> Bool
    let onHeld: () -> Void

    func makeUIView(context: Context) -> GuardView { GuardView() }

    func updateUIView(_ view: GuardView, context: Context) {
        view.shouldHold = shouldHold
        view.onHeld = onHeld
        view.install()
    }

    final class GuardView: UIView {
        var shouldHold: () -> Bool = { false }
        var onHeld: () -> Void = {}
        private let proxy = DelegateProxy()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            install()
        }

        func install() {
            guard window != nil,
                  let (tabBarController, tabViewController) = enclosingTab() else { return }
            proxy.tabViewController = tabViewController
            proxy.shouldHold = { [weak self] in self?.shouldHold() ?? false }
            proxy.onHeld = { [weak self] in self?.onHeld() }
            // SwiftUI may set its delegate again; stay in front of it.
            if tabBarController.delegate !== proxy {
                proxy.original = tabBarController.delegate
                tabBarController.delegate = proxy
            }
        }

        /// The tab bar controller, and the child of it that holds this view.
        private func enclosingTab() -> (UITabBarController, UIViewController)? {
            var responder: UIResponder? = self
            while let next = responder?.next, !(next is UIViewController) { responder = next }
            var controller = responder?.next as? UIViewController
            while let current = controller {
                if let tabBarController = current.parent as? UITabBarController {
                    return (tabBarController, current)
                }
                controller = current.parent
            }
            return nil
        }
    }

    /// Answers "should this tab be selected?" for a repeat tap on the
    /// guarded tab, and forwards every other delegate call to SwiftUI's.
    final class DelegateProxy: NSObject, UITabBarControllerDelegate {
        weak var original: UITabBarControllerDelegate?
        weak var tabViewController: UIViewController?
        var shouldHold: () -> Bool = { false }
        var onHeld: () -> Void = {}

        private func holds(_ tabBarController: UITabBarController, _ selecting: UIViewController?) -> Bool {
            guard let selecting, selecting === tabViewController,
                  tabBarController.selectedViewController === selecting,
                  shouldHold() else { return false }
            onHeld()
            return true
        }

        func tabBarController(_ tabBarController: UITabBarController,
                              shouldSelect viewController: UIViewController) -> Bool {
            if holds(tabBarController, viewController) { return false }
            return original?.tabBarController?(tabBarController, shouldSelect: viewController) ?? true
        }

        func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
            if holds(tabBarController, tab.viewController) { return false }
            return original?.tabBarController?(tabBarController, shouldSelectTab: tab) ?? true
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (original?.responds(to: selector) ?? false)
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            original?.responds(to: selector) == true ? original : nil
        }
    }
}
#endif
