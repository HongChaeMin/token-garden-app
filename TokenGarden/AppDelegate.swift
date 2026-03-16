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
    private var refreshTimer: Timer!
    private var updateChecker: UpdateChecker!

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single instance guard
        let bundleId = Bundle.main.bundleIdentifier ?? "com.tokengarden"
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        if running.count > 1 {
            NSApp.terminate(nil)
            return
        }

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
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // MenuBar Controller — start with zeros, load real data async
        menuBarController = MenuBarController(statusItem: statusItem, initialTodayTokens: 0, initialHourlyBuckets: [0, 0, 0])

        // Animation timer — runs forever, .common mode so it works during popover interaction
        animationTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.menuBarController.tick()
            }
        }
        RunLoop.main.add(animationTimer, forMode: .common)

        // Update checker
        updateChecker = UpdateChecker()
        updateChecker.check()

        // Popover — dynamic height, transient behavior closes on outside click
        popover = NSPopover()
        popover.behavior = .transient

        let popoverView = PopoverView()
            .environmentObject(menuBarController)
            .environmentObject(updateChecker)
            .modelContainer(modelContainer)
        let hostingController = NSHostingController(rootView: popoverView)
        hostingController.sizingOptions = .preferredContentSize
        popover.contentViewController = hostingController

        // Log Parser + Watcher — setup synchronously, heavy work async
        let parser = ClaudeCodeLogParser()
        logWatcher = LogWatcher(watchPaths: parser.watchPaths) { [weak self] line in
            guard let event = parser.parse(logLine: line) else { return }
            self?.dataStore.record(event)
            self?.menuBarController.onTokenEvent(event)
        }

        // Heavy startup work — run async to avoid blocking app launch
        Task { @MainActor in
            logWatcher.backfill()
            dataStore.flush()

            // refreshActiveStatus runs ps+lsof on background, updates DB on MainActor
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.dataStore.refreshActiveStatus()
            }

            // Update menu bar with real data after backfill
            let todayTokens = dataStore.fetchDailyUsages(
                from: Calendar.current.startOfDay(for: Date()),
                to: Date()
            ).first?.totalTokens ?? 0
            let hourlyBuckets = dataStore.fetchHourlyBuckets()
            menuBarController.reloadData(todayTokens: todayTokens, hourlyBuckets: hourlyBuckets)

            logWatcher.start()
        }

        // Periodic refresh of active sessions (every 30s)
        refreshTimer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .utility).async {
                self?.dataStore.refreshActiveStatus()
            }
        }
        RunLoop.main.add(refreshTimer, forMode: .common)
    }

    @MainActor @objc func togglePopover() {
        guard let event = NSApp.currentEvent else { return }

        // Right-click → show quit menu
        if event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Quit Token Garden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            // Clear menu after it closes so left-click works for popover
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.statusItem.menu = nil
            }
            return
        }

        // Left-click → toggle popover
        guard statusItem.menu == nil else { return }
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
