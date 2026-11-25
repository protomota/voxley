import AppKit
import Foundation
import Observation

/// Counts finished dictations and decides when the support card may appear.
/// Voxley ships only as a direct download, so it always uses custom reminders.
@MainActor
@Observable
final class VoxleyEngagement {
    static let shared = VoxleyEngagement()
    static let countKey = "voxleyCompletedDictations"
    static let clicksKey = "voxleySupportClickedActions.v1"
    static let presentedCountKey = "voxleySupportPresentedDictationCount.v1"
    static let stoppedKey = "voxleySupportAutomaticRemindersStopped.v1"
    static let reminderInterval = 5
    nonisolated static let website = URL(string: "https://voxley.si/")!
    nonisolated static let protomotaAppsURL = URL(string: "https://protomota.com/apps")!
    nonisolated static let tipURL = URL(string: "https://buymeacoffee.com/protomotalab")!
    nonisolated static let feedbackURL = URL(string: "https://protomota.com/apps?app=voxley#feedback")!
    nonisolated static let ticketURL = URL(string: "https://protomota.com/support?app=voxley")!

    enum Action: String, CaseIterable { case review, tip, share, feedback, support }
    static let dismissingActions = Set(Action.allCases)

    private(set) var completedDictations: Int
    private(set) var clickedActions: Set<Action>
    private(set) var automaticRemindersStopped: Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var lastPromptCount = -1

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        completedDictations = max(0, defaults.integer(forKey: Self.countKey))
        let storedClicks = Set((defaults.stringArray(forKey: Self.clicksKey) ?? []).compactMap(Action.init(rawValue:)))
        let stopped = defaults.bool(forKey: Self.stoppedKey) || !storedClicks.isDisjoint(with: Self.dismissingActions)
        clickedActions = storedClicks
        automaticRemindersStopped = stopped
        if stopped { defaults.set(true, forKey: Self.stoppedKey) }
    }

    /// Call only for a real dictation that produced text. Practice runs, cancels and errors never count.
    func completedDictation(text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        completedDictations = min(max(completedDictations, defaults.integer(forKey: Self.countKey)), 1_000_000_000) + 1
        defaults.set(completedDictations, forKey: Self.countKey)
    }

    func hasClicked(_ action: Action) -> Bool {
        (defaults.stringArray(forKey: Self.clicksKey) ?? []).contains(action.rawValue)
    }

    func recordClick(_ action: Action) {
        var actions = Set((defaults.stringArray(forKey: Self.clicksKey) ?? []).compactMap(Action.init(rawValue:)))
        actions.insert(action)
        defaults.set(actions.map(\.rawValue).sorted(), forKey: Self.clicksKey)
        clickedActions = actions
        if Self.dismissingActions.contains(action) {
            automaticRemindersStopped = true
            defaults.set(true, forKey: Self.stoppedKey)
        }
    }

    func supportCardOpened() {
        defaults.set(completedDictations, forKey: Self.presentedCountKey)
    }

    /// Clears the checkmarks only. Reminders retired by a support action stay off.
    func resetClickedActions() {
        defaults.removeObject(forKey: Self.clicksKey)
        clickedActions = []
        supportCardOpened()
    }

    var hasPendingSupportReminder: Bool {
        completedDictations >= Self.reminderInterval
            && completedDictations >= defaults.integer(forKey: Self.presentedCountKey) + Self.reminderInterval
            && !defaults.bool(forKey: Self.stoppedKey)
            && Self.dismissingActions.allSatisfy { !hasClicked($0) }
    }

    /// Claim before presenting so one milestone never shows the card twice.
    func claimPrompt(isIdle: Bool) -> Bool {
        guard isIdle, completedDictations != lastPromptCount, hasPendingSupportReminder else { return false }
        supportCardOpened()
        lastPromptCount = completedDictations
        return true
    }
}

/// Waits for Voxley to sit idle after a dictation, then shows the support card once.
@MainActor
final class VoxleySupportPrompter {
    static let idleSeconds = 11
    private let engagement: VoxleyEngagement
    private let isIdle: () -> Bool
    private let canPresent: () -> Bool
    private let present: () -> Void
    private let withdraw: () -> Void
    private var task: Task<Void, Never>?

    init(engagement: VoxleyEngagement = .shared, isIdle: @escaping () -> Bool,
         canPresent: @escaping () -> Bool, present: @escaping () -> Void, withdraw: @escaping () -> Void) {
        self.engagement = engagement
        self.isIdle = isIdle
        self.canPresent = canPresent
        self.present = present
        self.withdraw = withdraw
    }

    /// Restart the idle wait. Called after every finished dictation.
    func dictationFinished() {
        task?.cancel()
        guard engagement.hasPendingSupportReminder else { return }
        task = Task { [weak self] in await self?.waitAndPresent() }
    }

    /// A new dictation hides an automatic card and cancels a pending one.
    func dictationStarted() {
        task?.cancel()
        withdraw()
    }

    private func waitAndPresent() async {
        var idleFor = 0
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard engagement.hasPendingSupportReminder else { return }
            idleFor = isIdle() ? idleFor + 1 : 0
            guard idleFor >= Self.idleSeconds, canPresent() else { continue }
            if engagement.claimPrompt(isIdle: true) { present() }
            return
        }
    }
}
