import Foundation
import Testing
@testable import Voxley

@MainActor
private func freshEngagement(_ name: String = #function) -> (VoxleyEngagement, UserDefaults) {
    let suite = "voxley.tests.\(name).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return (VoxleyEngagement(defaults: defaults), defaults)
}

@MainActor
private func dictate(_ engagement: VoxleyEngagement, times: Int) {
    for _ in 0..<times { engagement.completedDictation(text: "Hello there") }
}

@MainActor @Test func emptyDictationsNeverCount() {
    let (engagement, _) = freshEngagement()
    engagement.completedDictation(text: "   \n")
    #expect(engagement.completedDictations == 0)
}

@MainActor @Test func countIsUncappedAndPersisted() {
    let (engagement, defaults) = freshEngagement()
    dictate(engagement, times: 12)
    #expect(engagement.completedDictations == 12)
    #expect(VoxleyEngagement(defaults: defaults).completedDictations == 12)
}

@MainActor @Test func cardWaitsForFiveDictations() {
    let (engagement, _) = freshEngagement()
    dictate(engagement, times: 4)
    #expect(!engagement.hasPendingSupportReminder)
    #expect(!engagement.claimPrompt(isIdle: true))
    dictate(engagement, times: 1)
    #expect(engagement.hasPendingSupportReminder)
    #expect(!engagement.claimPrompt(isIdle: false))
    #expect(engagement.claimPrompt(isIdle: true))
    #expect(!engagement.claimPrompt(isIdle: true))
}

@MainActor @Test func dismissedCardReturnsAfterFiveMore() {
    let (engagement, defaults) = freshEngagement()
    dictate(engagement, times: 5)
    #expect(engagement.claimPrompt(isIdle: true))
    dictate(engagement, times: 4)
    #expect(!engagement.hasPendingSupportReminder)
    dictate(engagement, times: 1)
    #expect(engagement.hasPendingSupportReminder)
    // A relaunch keeps the milestone it last presented.
    #expect(VoxleyEngagement(defaults: defaults).claimPrompt(isIdle: true))
}

@MainActor @Test func anyActionStopsRemindersPermanently() {
    for action in VoxleyEngagement.Action.allCases {
        let (engagement, defaults) = freshEngagement("anyAction-\(action.rawValue)")
        dictate(engagement, times: 5)
        engagement.recordClick(action)
        #expect(engagement.hasClicked(action))
        #expect(engagement.automaticRemindersStopped)
        dictate(engagement, times: 20)
        #expect(!engagement.hasPendingSupportReminder)
        let relaunched = VoxleyEngagement(defaults: defaults)
        #expect(relaunched.clickedActions == [action])
        #expect(!relaunched.claimPrompt(isIdle: true))
    }
}

@MainActor @Test func resetClearsCheckmarksButNeverRestartsReminders() {
    let (engagement, defaults) = freshEngagement()
    dictate(engagement, times: 5)
    engagement.recordClick(.tip)
    engagement.recordClick(.feedback)
    engagement.resetClickedActions()
    #expect(engagement.clickedActions.isEmpty)
    #expect(!engagement.hasClicked(.tip))
    #expect(engagement.automaticRemindersStopped)
    dictate(engagement, times: 20)
    #expect(!engagement.hasPendingSupportReminder)
    #expect(!VoxleyEngagement(defaults: defaults).hasPendingSupportReminder)
}

@MainActor @Test func openingTheCardManuallyDefersTheNextReminder() {
    let (engagement, _) = freshEngagement()
    dictate(engagement, times: 7)
    engagement.supportCardOpened()
    #expect(!engagement.hasPendingSupportReminder)
    dictate(engagement, times: 5)
    #expect(engagement.hasPendingSupportReminder)
}

@MainActor @Test func prompterPresentsOnlyAfterElevenIdleSeconds() async throws {
    #expect(VoxleySupportPrompter.idleSeconds == 11)
    let (engagement, _) = freshEngagement()
    dictate(engagement, times: 5)
    var presented = 0
    var idle = false
    let prompter = VoxleySupportPrompter(engagement: engagement, isIdle: { idle }, canPresent: { true },
                                         present: { presented += 1 }, withdraw: {})
    prompter.dictationFinished()
    try await Task.sleep(for: .seconds(3))
    #expect(presented == 0)
    idle = true
    try await Task.sleep(for: .seconds(9))
    #expect(presented == 0)
    try await Task.sleep(for: .seconds(3.5))
    #expect(presented == 1)
    #expect(!engagement.hasPendingSupportReminder)
}

@MainActor @Test func newDictationCancelsAPendingCard() async throws {
    let (engagement, _) = freshEngagement()
    dictate(engagement, times: 5)
    var presented = 0
    var withdrawn = 0
    let prompter = VoxleySupportPrompter(engagement: engagement, isIdle: { true }, canPresent: { true },
                                         present: { presented += 1 }, withdraw: { withdrawn += 1 })
    prompter.dictationFinished()
    try await Task.sleep(for: .seconds(2))
    prompter.dictationStarted()
    try await Task.sleep(for: .seconds(11))
    #expect(presented == 0)
    #expect(withdrawn == 1)
    #expect(engagement.hasPendingSupportReminder)
}
