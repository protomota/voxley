import AppKit
import SwiftUI

@MainActor
final class AboutWindow {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 510, height: 640),
                styleMask: [.titled, .closable], backing: .buffered, defer: false
            )
            window.title = "About Voxley"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: VoxleyAbout())
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

struct VoxleyAbout: View {
    private static let website = URL(string: "https://voxley.si/")!
    private static let tipPage = URL(string: "https://buymeacoffee.com/protomotalab")!
    private static let moreApps = URL(string: "https://protomota.com/apps")!

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private var appIcon: NSImage {
        Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            .flatMap(NSImage.init(contentsOf:)) ?? NSApp.applicationIconImage
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(nsImage: appIcon)
                        .resizable().scaledToFit().frame(width: 62, height: 62)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Voxley").font(.largeTitle.weight(.semibold))
                        Text("Version \(version) · Made by Protomota")
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Private dictation for Mac. Speak wherever you type, with transcription on your device.")
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Free software. Supported by people.")
                        .font(.headline)
                    Text("Every feature is free. Tips are entirely optional.")
                        .foregroundStyle(.secondary)
                    Link(destination: Self.tipPage) {
                        supportRow("Buy me a coffee", detail: "Leave an optional tip",
                                   icon: "cup.and.saucer")
                    }
                    Link(destination: VoxleySupport.feedbackURL) {
                        supportRow("Send Feedback", detail: "Suggest an improvement or report a bug",
                                   icon: "bubble.left.and.bubble.right")
                    }
                    ShareLink(item: Self.website, subject: Text("Voxley for Mac"),
                              message: Text("Free, private dictation for Mac.")) {
                        supportRow("Share Voxley", detail: "Send someone a link to the app",
                                   icon: "square.and.arrow.up")
                    }
                    Link(destination: VoxleySupport.ticketURL) {
                        supportRow("Open a Support Ticket", detail: "Get help with one issue in Voxley for Mac",
                                   icon: "headphones")
                    }
                    Link(destination: Self.moreApps) {
                        supportRow("More Free Apps by Protomota", detail: "Explore more apps from our studio",
                                   icon: "arrow.up.right.square")
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Follow Voxley").font(.headline)
                    GlassEffectContainer(spacing: 4) {
                        HStack(spacing: 10) {
                            followLink("Website", icon: "globe", destination: Self.website)
                            followLink("Protomota newsletter", icon: "envelope",
                                       destination: URL(string: "https://newsletter.protomota.com/")!)
                            followLink("Follow on X", icon: "arrow.up.right",
                                       destination: URL(string: "https://x.com/ProtomotaLab")!)
                        }
                    }
                }
                Text("© 2026 Protomota, LLC").font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 540, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func followLink(_ title: LocalizedStringKey, icon: String, destination: URL) -> some View {
        Link(destination: destination) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(Color.voxleyAccent)
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .glassEffect(.regular.interactive(), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func supportRow(_ title: LocalizedStringKey, detail: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.voxleyAccent)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.voxleyAccent)
                .accessibilityHidden(true)
        }
        .padding(10)
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
