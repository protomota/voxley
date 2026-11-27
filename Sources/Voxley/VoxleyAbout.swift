import AppKit
import SwiftUI

@MainActor
final class AboutWindow {
    private var window: NSWindow?

    func show(openSupport: @escaping () -> Void) {
        if window == nil {
            let window = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 510, height: 640),
                styleMask: [.titled, .closable], backing: .buffered, defer: false
            )
            window.title = "About Voxley"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: VoxleyAbout(openSupport: openSupport))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

struct VoxleyAbout: View {
    private static let website = VoxleyEngagement.website
    let openSupport: () -> Void

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
                        Text("Version \(version) · A Project ATOM project")
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Private dictation for Mac. Speak wherever you type, with transcription on your device.")
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Support Voxley").font(.headline)
                    VoxleySupportLinks(openSupport: openSupport)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Follow Voxley").font(.headline)
                    GlassEffectContainer(spacing: 4) {
                        HStack(spacing: 10) {
                            followLink("Website", icon: "globe", destination: Self.website)
                            followLink("Project ATOM", icon: "atom", destination: VoxleyEngagement.atomURL)
                        }
                    }
                }
                Text("A community is coming. Check back at projectatom.ai")
                    .font(.callout).foregroundStyle(.secondary)
                Text("A Project ATOM project").font(.caption).foregroundStyle(.secondary)
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
}
