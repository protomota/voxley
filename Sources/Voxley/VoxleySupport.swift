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
                            row("Get Help", detail: "Ask a real person through the feedback form",
                                icon: "headphones", kind: .support)
                        }
                        .accessibilityIdentifier("voxleySupportTicket")
                        Button { visit(.apps, url: VoxleyEngagement.atomAppsURL) } label: {
                            row("More Free Apps from Project ATOM", detail: "Explore more free apps from Project ATOM",
                                icon: "arrow.up.right.square", kind: .apps)
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
        Text(statusText)
            .font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var statusText: String {
        if engagement.allBoxesChecked { return "Every box is checked. Thank you for supporting Voxley." }
        return "Checkmarks show which buttons you’ve opened."
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Every dictation feature is free.\nNo account, no API key, nothing to unlock.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                if isAutomatic {
                    Button {
                        engagement.dismissForever()
                        dismiss()
                    } label: {
                        Text("Don’t show again")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("voxleySupportDontShowAgain")
                }
                Spacer(minLength: 24)
                Button(action: dismiss) {
                    Text(isAutomatic ? "Later" : "Back to Settings")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 22)
                        .frame(minHeight: 40)
                        .glassEffect(.regular.tint(Color.voxleyAccent.opacity(0.42)).interactive(), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("voxleySupportDismiss")
            }
        }
    }

    private func visit(_ action: VoxleyEngagement.Action, url: URL) {
        let finished = engagement.recordClick(action)
        openURL(url)
        if finished, isAutomatic { dismiss() }
    }

    private func share() {
        engagement.recordClick(.share)
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

/// Settings rows for support, feedback, free help and the other Project ATOM apps.
struct VoxleySupportLinks: View {
    let openSupport: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: openSupport) {
                linkRow("Share or send feedback", icon: "heart")
            }
            .accessibilityIdentifier("settingsSupportVoxley")
            Button {
                VoxleyEngagement.shared.recordClick(.review)
                openURL(VoxleyEngagement.feedbackURL)
            } label: {
                linkRow("Share Your Experience", icon: "star")
            }
            .accessibilityIdentifier("settingsRateVoxley")
            Button {
                VoxleyEngagement.shared.recordClick(.support)
                openURL(VoxleyEngagement.ticketURL)
            } label: {
                linkRow("Technical Support", detail: "Ask a real person through the feedback form",
                        icon: "headphones")
            }
            .accessibilityIdentifier("settingsTechnicalSupport")
            Button {
                VoxleyEngagement.shared.recordClick(.apps)
                openURL(VoxleyEngagement.atomAppsURL)
            } label: {
                linkRow("More Free Apps from Project ATOM", icon: "arrow.up.right.square")
            }
            .accessibilityIdentifier("settingsAtomApps")
            Button(action: openSupport) {
                linkRow("More Information & Support", icon: "info.circle")
            }
            .accessibilityIdentifier("settingsSupportVoxleyCard")
        }
        .buttonStyle(.plain)
    }

    private func linkRow(_ title: LocalizedStringKey, detail: LocalizedStringKey? = nil, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.voxleyAccent)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.semibold))
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
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
