import Foundation
import Testing
@testable import Voxley

@MainActor
private func freshDefaults(_ name: String = #function) -> UserDefaults {
    let suite = "voxley.tests.\(name).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@MainActor
private func dictate(_ engagement: VoxleyEngagement, times: Int) {
    for _ in 0..<times { engagement.completedDictation(text: "Hello there") }
}

private let day: TimeInterval = 24 * 60 * 60
private let start = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor @Test func emptyDictationsNeverCount() {
    let engagement = VoxleyEngagement(defaults: freshDefaults())
    engagement.completedDictation(text: "   \n")
    #expect(engagement.completedDictations == 0)
}

@MainActor @Test func countIsPersisted() {
    let defaults = freshDefaults()
    dictate(VoxleyEngagement(defaults: defaults), times: 12)
    #expect(VoxleyEngagement(defaults: defaults).completedDictations == 12)
}

@MainActor @Test func cardWaitsForFiveDictations() {
    let engagement = VoxleyEngagement(defaults: freshDefaults())
    dictate(engagement, times: 4)
    #expect(!engagement.claimPrompt(now: start))
    dictate(engagement, times: 1)
    #expect(engagement.claimPrompt(now: start))
}

@MainActor @Test func cardReturnsAtMostOnceEverySevenDays() {
    let defaults = freshDefaults()
    let engagement = VoxleyEngagement(defaults: defaults)
    dictate(engagement, times: 5)
    #expect(engagement.claimPrompt(now: start))
    dictate(engagement, times: 30)
    #expect(!engagement.claimPrompt(now: start.addingTimeInterval(1)))
    #expect(!engagement.claimPrompt(now: start.addingTimeInterval(7 * day - 60)))
    // The wait survives a relaunch.
    #expect(!VoxleyEngagement(defaults: defaults).hasPendingSupportReminder(now: start.addingTimeInterval(6 * day)))
    #expect(engagement.claimPrompt(now: start.addingTimeInterval(7 * day)))
    #expect(!engagement.claimPrompt(now: start.addingTimeInterval(8 * day)))
}

@MainActor @Test func oneClickDoesNotStopTheCard() {
    let engagement = VoxleyEngagement(defaults: freshDefaults())
    dictate(engagement, times: 5)
    #expect(engagement.claimPrompt(now: start))
    #expect(!engagement.recordClick(.feedback))
    #expect(!engagement.recordClick(.review))
    #expect(engagement.hasClicked(.feedback))
    #expect(engagement.claimPrompt(now: start.addingTimeInterval(7 * day)))
}

@MainActor @Test func cardStopsOnceEveryBoxIsChecked() {
    let defaults = freshDefaults()
    let engagement = VoxleyEngagement(defaults: defaults)
    dictate(engagement, times: 5)
    let boxes: [VoxleyEngagement.Action] = [.feedback, .share, .support, .apps]
    for (index, action) in boxes.enumerated() {
        #expect(engagement.recordClick(action) == (index == boxes.count - 1))
    }
    #expect(engagement.allBoxesChecked)
    #expect(!engagement.claimPrompt(now: start.addingTimeInterval(30 * day)))
    let relaunched = VoxleyEngagement(defaults: defaults)
    #expect(relaunched.clickedActions == Set(boxes))
    #expect(!relaunched.hasPendingSupportReminder(now: start.addingTimeInterval(60 * day)))
}

@MainActor @Test func dontShowAgainStopsTheCardAfterRelaunch() {
    let defaults = freshDefaults()
    let engagement = VoxleyEngagement(defaults: defaults)
    dictate(engagement, times: 5)
    #expect(engagement.claimPrompt(now: start))
    engagement.dismissForever()
    #expect(!engagement.claimPrompt(now: start.addingTimeInterval(8 * day)))
    let relaunched = VoxleyEngagement(defaults: defaults)
    dictate(relaunched, times: 20)
    #expect(relaunched.dismissedForever)
    #expect(!relaunched.hasPendingSupportReminder(now: start.addingTimeInterval(365 * day)))
}

@MainActor @Test func laterBringsTheCardBackAfterAWeek() {
    let engagement = VoxleyEngagement(defaults: freshDefaults())
    dictate(engagement, times: 5)
    #expect(engagement.claimPrompt(now: start))
    #expect(!engagement.claimPrompt(now: start.addingTimeInterval(6 * day)))
    #expect(engagement.claimPrompt(now: start.addingTimeInterval(7 * day)))
}

@MainActor @Test func earlierOptOutStillCounts() {
    let defaults = freshDefaults()
    defaults.set(true, forKey: "voxleySupportOptedOut.v2")
    let engagement = VoxleyEngagement(defaults: defaults)
    dictate(engagement, times: 5)
    #expect(!engagement.claimPrompt(now: start))
}

@MainActor @Test func olderAnyClickStopIsNotAnOptOut() {
    let defaults = freshDefaults()
    defaults.set(9, forKey: VoxleyEngagement.countKey)
    defaults.set(["feedback", "tip"], forKey: VoxleyEngagement.clicksKey)
    defaults.set(true, forKey: "voxleySupportAutomaticRemindersStopped.v1")
    defaults.set(5, forKey: "voxleySupportPresentedDictationCount.v1")
    let engagement = VoxleyEngagement(defaults: defaults)
    #expect(engagement.clickedActions == [.feedback])
    #expect(engagement.claimPrompt(now: start))
    #expect(defaults.object(forKey: "voxleySupportAutomaticRemindersStopped.v1") == nil)
}

@MainActor @Test func prompterPresentsOnlyAfterElevenIdleSeconds() async throws {
    #expect(VoxleySupportPrompter.idleSeconds == 11)
    let engagement = VoxleyEngagement(defaults: freshDefaults())
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
    #expect(!engagement.hasPendingSupportReminder())
}

@MainActor @Test func newDictationCancelsAPendingCard() async throws {
    let engagement = VoxleyEngagement(defaults: freshDefaults())
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
    #expect(engagement.hasPendingSupportReminder())
}
