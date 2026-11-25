import AppKit
import SwiftUI

/// The support card lives in its own panel because Voxley has no main window to attach a sheet to.
@MainActor
final class SupportWindow: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private(set) var isAutomatic = false

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(automatic: Bool) {
        isAutomatic = automatic
        let panel = panel ?? makePanel()
        panel.contentView = NSHostingView(rootView: VoxleySupportView(isAutomatic: automatic) { [weak self] in
            self?.close()
        })
        panel.setContentSize(NSSize(width: 600, height: 660))
        panel.center()
        self.panel = panel
        if automatic {
            // Appear without taking keyboard focus from the app the person is writing in.
            panel.orderFrontRegardless()
        } else {
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func close() { panel?.close() }

    func withdrawAutomatic() {
        if isAutomatic, isVisible { close() }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 660),
                            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.title = "Support Voxley"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.delegate = self
        return panel
    }
}

struct VoxleySupportView: View {
    var engagement = VoxleyEngagement.shared
    var isAutomatic = false
    let dismiss: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var didReset = false
    @State private var shareAnchor = NSView()

    private var appIcon: NSImage {
        Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            .flatMap(NSImage.init(contentsOf:)) ?? NSApp.applicationIconImage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.bottom, 22)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 10) {
                        Button { visit(.tip, url: VoxleyEngagement.tipURL) } label: {
                            row("Buy Me a Coffee", detail: "Opens Buy Me a Coffee in your browser",
                                icon: "cup.and.saucer", kind: .tip)
                        }
                        .accessibilityIdentifier("voxleySupportTip")
                        Button { visit(.feedback, url: VoxleyEngagement.feedbackURL) } label: {
                            row("Send Feedback", detail: "Help shape what comes next",
                                icon: "bubble.left.and.bubble.right", kind: .feedback)
                        }
                        .accessibilityIdentifier("voxleySupportFeedback")
                        Button(action: share) {
                            row("Share Voxley", detail: "Help others discover private dictation",
                                icon: "square.and.arrow.up", kind: .share)
                        }
                        .background(SupportShareAnchor(view: shareAnchor))
                        .accessibilityIdentifier("voxleySupportShare")
                        Button { visit(.support, url: VoxleyEngagement.ticketURL) } label: {
                            row("Open a Support Ticket", detail: "Create a ticket or follow replies on Protomota",
                                icon: "headphones", kind: .support)
                        }
                        .accessibilityIdentifier("voxleySupportTicket")
                        Link(destination: VoxleyEngagement.protomotaAppsURL) {
                            row("More Free Apps by Protomota", detail: "Explore more free apps from our studio",
                                icon: "arrow.up.right.square")
                        }
                        .accessibilityIdentifier("voxleySupportApps")
                    }
                    .buttonStyle(.plain)
                    status
                }
                .padding(.trailing, 2)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer.padding(.top, 22)
        }
        .padding(30)
        .padding(.top, 8)
        .frame(width: 600, height: 660)
        .tint(.voxleyAccent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voxleySupportCard")
        .onAppear { engagement.supportCardOpened() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: appIcon)
                .resizable().scaledToFit().frame(width: 62, height: 62)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(isAutomatic ? "YOUR DICTATION, SAVED" : "RATINGS & SUPPORT")
                    .font(.system(size: 12, weight: .bold)).tracking(1.4)
                    .foregroundStyle(Color.voxleyAccent)
                Text("Free software.\nSupported by people.")
                    .font(.system(size: 28, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close support message")
            .accessibilityIdentifier("voxleySupportClose")
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(statusText)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Reset saved clicks") {
                engagement.resetClickedActions()
                didReset = true
            }
            .buttonStyle(.plain)
            .font(.callout.weight(.medium))
            .foregroundStyle(Color.voxleyAccent)
            .padding(.vertical, 6)
            .accessibilityIdentifier("voxleySupportReset")
        }
    }

    private var statusText: String {
        if didReset {
            return engagement.automaticRemindersStopped
                ? "Saved clicks reset. Automatic reminders stay off." : "Saved clicks reset."
        }
        return (engagement.automaticRemindersStopped
                ? "Automatic reminders are off. " : "Any one action turns off automatic reminders. ")
            + "Checkmarks remember clicks, not completed reviews, tips or shares."
    }

    private var footer: some View {
        HStack(spacing: 18) {
            Text("Dictation features stay free.\nPaid support and tips are optional.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Text(isAutomatic ? "Back to Dictation" : "Back to Settings")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 18)
                    .frame(minHeight: 36)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("voxleySupportDismiss")
        }
    }

    private func visit(_ action: VoxleyEngagement.Action, url: URL) {
        engagement.recordClick(action)
        didReset = false
        openURL(url)
        dismiss()
    }

    private func share() {
        engagement.recordClick(.share)
        didReset = false
        SupportSharing.shared.present(from: shareAnchor)
    }

    private func row(_ title: LocalizedStringKey, detail: LocalizedStringKey, icon: String,
                     kind: VoxleyEngagement.Action? = nil) -> some View {
        let clicked = kind.map { engagement.clickedActions.contains($0) } ?? false
        return HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Color.voxleyAccent)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Image(systemName: clicked ? "checkmark.circle.fill" : "arrow.up.right")
                .font(.system(size: clicked ? 16 : 13, weight: .semibold))
                .foregroundStyle(Color.voxleyAccent)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(clicked ? AnyShapeStyle(Color.voxleyAccent.opacity(0.7)) : AnyShapeStyle(.quaternary))
                .allowsHitTesting(false)
        }
        .contentShape(.rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityValue(clicked ? Text("Previously clicked") : Text(""))
    }
}

/// Settings rows that lead to feedback, the support card and Protomota's other apps.
struct VoxleySupportLinks: View {
    let openSupport: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                VoxleyEngagement.shared.recordClick(.review)
                openURL(VoxleyEngagement.feedbackURL)
            } label: {
                linkRow("Share Your Experience", icon: "star")
            }
            .accessibilityIdentifier("settingsRateVoxley")
            Button(action: openSupport) {
                linkRow("More Information & Support", icon: "heart")
            }
            .accessibilityIdentifier("settingsSupportVoxleyCard")
            Link(destination: VoxleyEngagement.protomotaAppsURL) {
                linkRow("More Free Apps by Protomota", icon: "arrow.up.right.square")
            }
            .accessibilityIdentifier("settingsProtomotaApps")
        }
        .buttonStyle(.plain)
    }

    private func linkRow(_ title: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.voxleyAccent)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(title).font(.callout.weight(.semibold))
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.voxleyAccent)
                .accessibilityHidden(true)
        }
        .padding(10)
        .frame(minHeight: 40)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.quaternary)
                .allowsHitTesting(false)
        }
        .contentShape(.rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

private struct SupportShareAnchor: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Retains the picker so it survives SwiftUI updates while it is open.
@MainActor
private final class SupportSharing: NSObject, @MainActor NSSharingServicePickerDelegate {
    static let shared = SupportSharing()
    private var picker: NSSharingServicePicker?

    func present(from anchor: NSView) {
        guard anchor.window != nil else { return }
        let picker = NSSharingServicePicker(items: [VoxleyEngagement.website])
        picker.delegate = self
        self.picker = picker
        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        picker = nil
    }
}
