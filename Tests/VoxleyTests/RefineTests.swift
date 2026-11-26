import Foundation
import Testing
@testable import Voxley

@Test func refineSettingsDefaultOnForLibrariesSavedBeforeRefine() throws {
    var library = Library()
    library.preferences.mode = .clean
    var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(library)) as? [String: Any])
    var preferences = try #require(json["preferences"] as? [String: Any])
    preferences.removeValue(forKey: "refineShortcut")
    preferences.removeValue(forKey: "refineDisabled")
    json["preferences"] = preferences

    let decoded = try JSONDecoder().decode(Library.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(decoded.preferences.mode == .clean)
    #expect(decoded.preferences.refineEnabled)
    #expect(decoded.preferences.refineShortcutKey == .refineDefault)
    #expect(decoded.preferences.shortcutKey == .controlShiftSpace)
}

@Test func refineShortcutIsSeparateFromTheDictationShortcut() throws {
    #expect(Shortcut.refineDefault.label == "⌃⌥R")
    #expect(Shortcut.refineDefault != Shortcut.controlShiftSpace)
    #expect(!Shortcut.refineDefault.isStandardEditingShortcut)

    var preferences = Preferences()
    preferences.refineEnabled = false
    preferences.refineShortcutKey = Shortcut(code: 15, modifiers: Shortcut.refineDefault.modifiers, keyLabel: "R")
    let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
    #expect(!restored.refineEnabled)
    #expect(restored.refineShortcutKey.label == "⌃⌥R")
    preferences.refineEnabled = true
    #expect(preferences.refineDisabled == nil)
}

@Test func refinePromptCarriesTheCurrentDraftAndRequest() {
    let first = RefinePrompt.turn(draft: "um so the idea is a weekly digest", request: "  ")
    #expect(first.contains(RefinePrompt.defaultRequest))
    #expect(first.hasSuffix("um so the idea is a weekly digest"))

    let next = RefinePrompt.turn(draft: "A weekly digest.", request: "make it friendlier")
    #expect(next.hasPrefix("Request: make it friendlier"))
    #expect(next.contains("Current draft:\nA weekly digest."))
}
