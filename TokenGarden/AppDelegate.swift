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
    private var animationTimer: Timer!

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // SwiftData — explicit store path + lightweight migration
        let schema = Schema([DailyUsage.self, ProjectUsage.self, SessionUsage.self])
        let storeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TokenGarden", isDirectory: true)
            .appendingPathComponent("TokenGarden.store")
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let config = ModelConfiguration("TokenGarden", schema: schema, url: storeURL)
        modelContainer = try! ModelContainer(for: schema, configurations: [config])
        dataStore = TokenDataStore(modelContainer: modelContainer)

        // Status Item — fixed width to prevent menu bar shifting during animation
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = AnimationFrames.idleImage()
            button.action = #selector(togglePopover)
            button.target = self
        }

        // MenuBar Controller — load today's tokens from store
        let todayTokens = dataStore.fetchDailyUsages(
            from: Calendar.current.startOfDay(for: Date()),
            to: Date()
        ).first?.totalTokens ?? 0
        let hourlyBuckets = dataStore.fetchHourlyBuckets()
        menuBarController = MenuBarController(statusItem: statusItem, initialTodayTokens: todayTokens, initialHourlyBuckets: hourlyBuckets)

        // Animation timer — runs forever, .common mode so it works during popover interaction
        animationTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.menuBarController.tick()
            }
        }
        RunLoop.main.add(animationTimer, forMode: .common)

        // Popover — transient behavior closes on outside click
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 480)
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
        dataStore.flush()
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
