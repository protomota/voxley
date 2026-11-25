import AppKit
import Foundation
import Observation

/// Counts finished dictations and decides when the support card may appear.
/// Voxley ships only as a direct download, so it uses the custom card, never a store rating prompt.
/// The card returns at most once a week until every support box is checked or the person opts out.
@MainActor
@Observable
final class VoxleyEngagement {
    static let shared = VoxleyEngagement()
    static let countKey = "voxleyCompletedDictations"
    static let clicksKey = "voxleySupportClickedActions.v1"
    static let presentedAtKey = "voxleySupportPresentedAt.v2"
    static let optedOutKey = "voxleySupportOptedOut.v2"
    /// 1.0.14 stopped reminders after any click. Those flags are not opt-outs and are dropped.
    static let legacyKeys = ["voxleySupportAutomaticRemindersStopped.v1", "voxleySupportPresentedDictationCount.v1"]
    static let milestone = 5
    static let interval: TimeInterval = 7 * 24 * 60 * 60
    nonisolated static let website = URL(string: "https://voxley.si/")!
    nonisolated static let protomotaAppsURL = URL(string: "https://protomota.com/apps")!
    nonisolated static let tipURL = URL(string: "https://buymeacoffee.com/protomotalab")!
    nonisolated static let feedbackURL = URL(string: "https://protomota.com/apps?app=voxley#feedback")!
    nonisolated static let ticketURL = URL(string: "https://protomota.com/support?app=voxley")!

    enum Action: String, CaseIterable { case review, tip, feedback, share, support, apps }
    /// The five boxes on the card. Share Your Experience in Settings is tracked but not one of them.
    static let reminderActions: Set<Action> = [.tip, .feedback, .share, .support, .apps]

    private(set) var completedDictations: Int
    private(set) var clickedActions: Set<Action>
    private(set) var optedOut: Bool
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        completedDictations = max(0, defaults.integer(forKey: Self.countKey))
        clickedActions = Set((defaults.stringArray(forKey: Self.clicksKey) ?? []).compactMap(Action.init(rawValue:)))
        optedOut = defaults.bool(forKey: Self.optedOutKey)
        Self.legacyKeys.forEach(defaults.removeObject(forKey:))
    }

    /// Call only for a real dictation that produced text. Practice runs, cancels and errors never count.
    func completedDictation(text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        completedDictations = min(max(completedDictations, defaults.integer(forKey: Self.countKey)), 1_000_000_000) + 1
        defaults.set(completedDictations, forKey: Self.countKey)
    }

    func hasClicked(_ action: Action) -> Bool { clickedActions.contains(action) }

    var allBoxesChecked: Bool { Self.reminderActions.isSubset(of: clickedActions) }

    /// Saves the checkmark. Returns true once every box on the card is checked.
    @discardableResult
    func recordClick(_ action: Action) -> Bool {
        var actions = Set((defaults.stringArray(forKey: Self.clicksKey) ?? []).compactMap(Action.init(rawValue:)))
        actions.insert(action)
        defaults.set(actions.map(\.rawValue).sorted(), forKey: Self.clicksKey)
        clickedActions = actions
        return allBoxesChecked
    }

    func optOut() {
        optedOut = true
        defaults.set(true, forKey: Self.optedOutKey)
    }

    var remindersStopped: Bool { optedOut || allBoxesChecked }

    func hasPendingSupportReminder(now: Date = .now) -> Bool {
        guard completedDictations >= Self.milestone, !remindersStopped else { return false }
        let last = defaults.double(forKey: Self.presentedAtKey)
        return last == 0 || now.timeIntervalSince1970 - last >= Self.interval
    }

    /// Claim before presenting so one week never shows the card twice.
    func claimPrompt(now: Date = .now) -> Bool {
        guard hasPendingSupportReminder(now: now) else { return false }
        defaults.set(now.timeIntervalSince1970, forKey: Self.presentedAtKey)
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
        guard engagement.hasPendingSupportReminder() else { return }
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
            guard engagement.hasPendingSupportReminder() else { return }
            idleFor = isIdle() ? idleFor + 1 : 0
            guard idleFor >= Self.idleSeconds, canPresent() else { continue }
            if engagement.claimPrompt() { present() }
            return
        }
    }
}
