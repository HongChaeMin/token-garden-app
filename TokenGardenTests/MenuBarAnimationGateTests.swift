import Testing
import AppKit
import Foundation
@testable import TokenGarden

/// Verifies the idle animation gate added to `MenuBarController.tick()`.
/// The frame must only advance while there's been recent token activity —
/// the wasted NSImage regeneration while the machine is idle is the issue
/// the gate closes.
@MainActor
struct MenuBarAnimationGateTests {
    private func makeController() -> (controller: MenuBarController, statusBar: NSStatusBar, statusItem: NSStatusItem) {
        // Test-owned status item hosted by a private status bar instance, so
        // it does not touch NSStatusBar.system during the test run.
        let statusBar = NSStatusBar()
        let statusItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        let controller = MenuBarController(
            statusItem: statusItem,
            initialTodayTokens: 0,
            initialHourlyBuckets: [0, 0, 0],
            displayMode: { MenuBarDisplayMode.iconOnly.rawValue }
        )
        return (controller, statusBar, statusItem)
    }

    @Test func freshControllerIsNotAnimating() {
        let (c, statusBar, statusItem) = makeController()
        defer { statusBar.removeStatusItem(statusItem) }
        #expect(c.isAnimating == false)
    }

    @Test func tokenActivityStartsAnimation() {
        let (c, statusBar, statusItem) = makeController()
        defer { statusBar.removeStatusItem(statusItem) }
        c.onTokenUsage(at: Date(), tokens: 100)
        #expect(c.isAnimating == true)
    }

    @Test func idleThresholdIsAtLeastOneMinute() {
        let (_, statusBar, statusItem) = makeController()
        defer { statusBar.removeStatusItem(statusItem) }
        // Sanity: the gate shouldn't have been accidentally shortened to
        // something chatty like 1s — defeats the whole battery/CPU win.
        #expect(MenuBarController.idleThreshold >= 60)
    }
}
