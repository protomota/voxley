import AppKit
import SwiftUI

enum VoxleySupport {
    static let ticketURL = VoxleyEngagement.ticketURL
    static let feedbackURL = VoxleyEngagement.feedbackURL
}

@main
@MainActor
struct VoxleyApp: App {
    @NSApplicationDelegateAdaptor(VoxleyDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Voxley", systemImage: menuIcon) {
            MenuCommands(controller: delegate.controller, openOnboarding: delegate.openOnboarding,
                         openAbout: delegate.openAbout, openSupport: delegate.openSupport,
                         openRefine: delegate.openRefine)
        }

        Settings {
            VoxleySettings(controller: delegate.controller, launchAtLogin: delegate.launchAtLogin,
                           openOnboarding: delegate.openOnboarding, openAbout: delegate.openAbout,
                           openSupport: delegate.openSupport)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Voxley", action: delegate.openAbout)
            }
            CommandGroup(after: .appInfo) {
                Button("Voxley Onboarding…", action: delegate.openOnboarding)
            }
            CommandGroup(after: .help) {
                Button("Get App Help") { NSWorkspace.shared.open(VoxleySupport.ticketURL) }
                Button("Send Feedback…") { NSWorkspace.shared.open(VoxleySupport.feedbackURL) }
            }
        }
    }

    private var menuIcon: String {
        if delegate.controller.phase == .recording { return "mic.fill" }
        return delegate.controller.pasteNeedsAttention ? "exclamationmark.circle" : "waveform"
    }
}

@MainActor
final class VoxleyDelegate: NSObject, NSApplicationDelegate {
    let controller = DictationController()
    let launchAtLogin = LaunchAtLogin()
    private let recorder = RecorderPanel()
    private let refine = RefineWindow()
    private let setup = SetupWindow()
    private let about = AboutWindow()
    private let support = SupportWindow()
    private lazy var supportPrompter = VoxleySupportPrompter(
        isIdle: { [unowned self] in controller.phase == .idle },
        canPresent: { [unowned self] in canPresentSupport },
        present: { [unowned self] in support.show(automatic: true) },
        withdraw: { [unowned self] in support.withdrawAutomatic() }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchAtLogin.configureDefault()
        controller.activate()
        recorder.connect(controller)
        controller.onDictationStarted = { [unowned self] in supportPrompter.dictationStarted() }
        controller.onDictationFinished = { [unowned self] in supportPrompter.dictationFinished() }
        controller.onRefineReady = { [unowned self] text, target in
            refine.present(text, from: target, locale: controller.preferences.locale)
        }
        if CommandLine.arguments.contains("--refine-preview") {
            refine.openEmpty(locale: controller.preferences.locale)
        }
        if CommandLine.arguments.contains("--support-card") { openSupport() }
        if CommandLine.arguments.contains("--about") { openAbout() }
        if CommandLine.arguments.contains("--support-card-automatic") { support.show(automatic: true) }
        #if VOXLEY_SPARKLE
        VoxleyUpdates.shared.start(dictation: controller)
        #endif
        if CommandLine.arguments.contains("--onboarding") ||
            !UserDefaults.standard.bool(forKey: "didCompleteVoxleySetup") {
            openOnboarding()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        launchAtLogin.refresh()
        controller.refreshPermissions()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openOnboarding()
        return true
    }

    func openOnboarding() {
        // Let the menu finish closing before asking AppKit to activate the window.
        DispatchQueue.main.async { self.setup.show(self.controller) }
    }

    func openRefine() {
        DispatchQueue.main.async { self.refine.openEmpty(locale: self.controller.preferences.locale) }
    }

    func openAbout() { DispatchQueue.main.async { self.about.show(openSupport: self.openSupport) } }

    func openSupport() { DispatchQueue.main.async { self.support.show(automatic: false) } }

    /// The card waits while another Voxley window, sheet or modal is up, or while the person is typing.
    private var canPresentSupport: Bool {
        guard NSApp.modalWindow == nil, !support.isVisible, !setup.isVisible, !refine.isVisible else { return false }
        guard !NSApp.windows.contains(where: { $0.isVisible && $0.attachedSheet != nil }) else { return false }
        let sinceKey = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        return sinceKey >= 2
    }
}

private struct MenuCommands: View {
    let controller: DictationController
    let openOnboarding: () -> Void
    let openAbout: () -> Void
    let openSupport: () -> Void
    let openRefine: () -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Voxley Onboarding…", action: openOnboarding)
        Divider()
        Text("Tap or hold \(controller.preferences.shortcutKey.label) to dictate")
        if controller.preferences.refineEnabled {
            Text(controller.refineShortcutReady
                 ? "Tap or hold \(controller.preferences.refineShortcutKey.label) to dictate and refine"
                 : "Refine shortcut unavailable. Choose another in Settings.")
        }
        Button("Open Refine Window…", action: openRefine)

        if controller.phase.isCapturing {
            Button("Cancel Dictation") { controller.cancel() }
        }
        if let transcript = controller.mostRecentTranscript {
            Button("Copy Last Transcript") { Destination.copy(transcript.text) }
        }
        if let message = controller.message {
            Text(message)
        }
        if controller.pasteNeedsAttention, !controller.accessibilityReady {
            Button("Enable Automatic Paste…") { controller.allowAccessibility() }
        }
        if !controller.shortcutReady {
            Text("Choose an available shortcut in Voxley Onboarding.")
        }
        Divider()
        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        #if VOXLEY_SPARKLE
        Button("Check for Updates…", action: VoxleyUpdates.shared.check)
            .disabled(!VoxleyUpdates.shared.canCheck || controller.phase != .idle)
        #endif
        Button("About Voxley", action: openAbout)
        Button("Support Voxley…", action: openSupport)
        Button("Get App Help") { NSWorkspace.shared.open(VoxleySupport.ticketURL) }
        Button("Send Feedback…") { NSWorkspace.shared.open(VoxleySupport.feedbackURL) }
        Button("Quit Voxley") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
