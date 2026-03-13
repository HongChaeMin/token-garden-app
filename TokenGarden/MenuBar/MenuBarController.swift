import AppKit
import Combine

enum AnimationSpeed: TimeInterval {
    case slow = 1.0
    case medium = 0.33
    case fast = 0.167
}

@MainActor
class MenuBarController: ObservableObject {
    @Published var todayTokens: Int = 0

    private var animationTimer: Timer?
    private var idleTimer: Timer?
    private var currentFrame = 0
    private var recentTokens: [(date: Date, count: Int)] = []
    private weak var statusItem: NSStatusItem?

    private let animationEnabled: () -> Bool
    private let displayMode: () -> String

    init(
        statusItem: NSStatusItem,
        initialTodayTokens: Int = 0,
        animationEnabled: @escaping () -> Bool = {
            // UserDefaults.bool returns false if key doesn't exist,
            // so we check if the key was ever set. Default to true.
            if UserDefaults.standard.object(forKey: "animationEnabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "animationEnabled")
        },
        displayMode: @escaping () -> String = { UserDefaults.standard.string(forKey: "displayMode") ?? MenuBarDisplayMode.iconOnly.rawValue }
    ) {
        self.statusItem = statusItem
        self.todayTokens = initialTodayTokens
        self.animationEnabled = animationEnabled
        self.displayMode = displayMode
        updateDisplay()
    }

    func onTokenEvent(_ event: TokenEvent) {
        todayTokens += event.totalTokens
        recentTokens.append((date: Date(), count: event.totalTokens))
        recentTokens.removeAll { Date().timeIntervalSince($0.date) > 30 }

        updateDisplay()

        guard animationEnabled() else { return }
        updateAnimationSpeed()
        resetIdleTimer()
    }

    private func updateDisplay() {
        guard let button = statusItem?.button else { return }
        let mode = MenuBarDisplayMode(rawValue: displayMode()) ?? .iconOnly

        switch mode {
        case .iconOnly:
            button.title = ""
        case .iconAndNumber:
            button.title = " \(TokenFormatter.format(todayTokens))"
        case .iconAndMiniGraph:
            button.title = ""
        }

        if animationTimer == nil {
            button.image = AnimationFrames.image(for: 0)
        }
    }

    private func startAnimation(speed: AnimationSpeed) {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: speed.rawValue, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceFrame()
            }
        }
    }

    private func updateAnimationSpeed() {
        let speed = currentSpeed()
        startAnimation(speed: speed)
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        currentFrame = 0
        statusItem?.button?.image = AnimationFrames.image(for: 0)
    }

    private func advanceFrame() {
        currentFrame = (currentFrame + 1) % AnimationFrames.frames.count
        statusItem?.button?.image = AnimationFrames.image(for: currentFrame)
    }

    private func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.stopAnimation()
            }
        }
    }

    private func currentSpeed() -> AnimationSpeed {
        let recentTotal = recentTokens
            .filter { Date().timeIntervalSince($0.date) <= 30 }
            .reduce(0) { $0 + $1.count }

        if recentTotal > 10_000 { return .fast }
        if recentTotal > 1_000 { return .medium }
        return .slow
    }
}
