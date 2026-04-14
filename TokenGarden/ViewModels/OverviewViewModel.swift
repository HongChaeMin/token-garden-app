import Foundation
import Observation
import SwiftData

/// Main-actor @Observable view model that owns all Overview tab data.
///
/// The view reads `snapshot` (plus `selectedDate` state) directly.
/// All fetching is delegated to `OverviewRepository` which runs on a
/// background actor, so the view never blocks on DB I/O.
///
/// Optimistic rendering: after the first load, subsequent refreshes keep
/// `isInitialLoading = false` and update the snapshot in place. Stale data
/// stays visible during refresh instead of flashing skeletons.
@MainActor
@Observable
final class OverviewViewModel {
    /// Latest data, or `.empty` until the first load completes.
    private(set) var snapshot: OverviewSnapshot = .empty

    /// True while the very first load is in flight. Stays false during
    /// subsequent refreshes so the skeleton doesn't flash.
    private(set) var isInitialLoading: Bool = true

    /// Currently selected heatmap cell, if any. `didSet` fans out to
    /// `loadSelectedDateData` so the view never orchestrates fetches.
    var selectedDate: Date? = nil {
        didSet {
            guard oldValue != selectedDate else { return }
            loadSelectedDateData()
        }
    }

    /// Hourly tokens for the day the user is currently viewing (today by
    /// default, or the selected date) — per source.
    private(set) var activeClaudeHourlyTokens: [Int] = Array(repeating: 0, count: 24)
    private(set) var activeCodexHourlyTokens: [Int] = Array(repeating: 0, count: 24)

    /// Project breakdown for the selected day, or nil when no day is selected.
    private(set) var selectedDayProjects: [ProjectBreakdown]? = nil

    private let repository: OverviewRepository
    private var loadTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var selectedDateTask: Task<Void, Never>?

    init(modelContainer: ModelContainer) {
        self.repository = OverviewRepository(modelContainer: modelContainer)
    }

    /// Start the initial background load. Call once from AppDelegate at
    /// app launch — well before the user clicks the menu bar.
    func start() {
        refresh()
    }

    /// Reload the whole snapshot. Safe to call often — earlier tasks cancel.
    func refresh() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            let new = await self.repository.loadSnapshot()
            if Task.isCancelled { return }
            self.snapshot = new
            // Only reset active hourly when no day is selected — otherwise
            // we'd stomp the user's selection.
            if self.selectedDate == nil {
                self.activeClaudeHourlyTokens = new.claudeHourlyToday
                self.activeCodexHourlyTokens = new.codexHourlyToday
            }
            self.isInitialLoading = false
        }
    }

    /// Notify that a live token event arrived. Debounced to avoid refreshing
    /// on every single event during heavy activity.
    func onTokenEvent() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            if Task.isCancelled { return }
            self?.refresh()
        }
    }

    /// Wait for any in-flight load / selected-date-load tasks to finish.
    /// Intended for tests that need deterministic state after triggering
    /// `start()`, `refresh()`, or `selectedDate = ...`.
    func awaitPendingTasks() async {
        if let t = loadTask { await t.value }
        if let t = selectedDateTask { await t.value }
    }

    private func loadSelectedDateData() {
        selectedDateTask?.cancel()
        guard let date = selectedDate else {
            // Reset to today's view.
            activeClaudeHourlyTokens = snapshot.claudeHourlyToday
            activeCodexHourlyTokens = snapshot.codexHourlyToday
            selectedDayProjects = nil
            return
        }
        selectedDateTask = Task { [weak self] in
            guard let self else { return }
            async let hourly = self.repository.loadHourlyTokensBySource(for: date)
            async let projects = self.repository.loadProjects(for: date)
            let h = await hourly
            let p = await projects
            if Task.isCancelled { return }
            self.activeClaudeHourlyTokens = h.claude
            self.activeCodexHourlyTokens = h.codex
            self.selectedDayProjects = p
        }
    }
}
