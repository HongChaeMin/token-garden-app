import AppKit
import SwiftUI
import SwiftData

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var menuBarController: MenuBarController!
    private var logWatcher: LogWatcher!
    private var dataStore: TokenDataStore!
    private var modelContainer: ModelContainer!

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // SwiftData
        modelContainer = try! ModelContainer(for: DailyUsage.self, ProjectUsage.self)
        dataStore = TokenDataStore(modelContainer: modelContainer)

        // Status Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "Token Garden")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // MenuBar Controller — load today's tokens from store
        let todayTokens = dataStore.fetchDailyUsages(
            from: Calendar.current.startOfDay(for: Date()),
            to: Date()
        ).first?.totalTokens ?? 0
        menuBarController = MenuBarController(statusItem: statusItem, initialTodayTokens: todayTokens)

        // Popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient

        let popoverView = PopoverView()
            .environmentObject(menuBarController)
            .modelContainer(modelContainer)
        popover.contentViewController = NSHostingController(rootView: popoverView)

        // Log Parser + Watcher
        let parser = ClaudeCodeLogParser()
        logWatcher = LogWatcher(watchPaths: parser.watchPaths) { [weak self] line in
            guard let event = parser.parse(logLine: line) else { return }
            self?.dataStore.record(event)
            self?.menuBarController.onTokenEvent(event)
        }

        logWatcher.backfill()
        logWatcher.start()
    }

    @MainActor @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
