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
    private func makeController() -> MenuBarController {
        // Offscreen status item — not added to NSStatusBar.system but it's
        // enough to instantiate the controller without side-effects.
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        _ = statusItem
        return MenuBarController(
            statusItem: statusItem,
            initialTodayTokens: 0,
            initialHourlyBuckets: [0, 0, 0],
            displayMode: { MenuBarDisplayMode.iconOnly.rawValue }
        )
    }

    @Test func freshControllerIsNotAnimating() {
        let c = makeController()
        #expect(c.isAnimating == false)
    }

    @Test func tokenActivityStartsAnimation() {
        let c = makeController()
        c.onTokenUsage(at: Date(), tokens: 100)
        #expect(c.isAnimating == true)
    }

    @Test func idleThresholdIsAtLeastOneMinute() {
        // Sanity: the gate shouldn't have been accidentally shortened to
        // something chatty like 1s — defeats the whole battery/CPU win.
        #expect(MenuBarController.idleThreshold >= 60)
    }
}
