import AppKit
import SwiftUI

/// The small, static Refine window. It stays where it opens so the person can take their
/// hands off the shortcut, type, chat with Apple Intelligence, and copy the result.
@MainActor
final class RefineWindow: NSObject, NSWindowDelegate {
    let session = RefineSession()
    private var window: NSWindow?
    private var returnApp: NSRunningApplication?
    private let size = NSSize(width: 480, height: 560)

    var isVisible: Bool { window?.isVisible == true }

    /// Opens the window with a new transcript, or adds to the open conversation.
    func present(_ text: String, from target: Destination, locale: String) {
        if isVisible, target.app?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            session.receiveSpokenRequest(text)
            window?.makeKeyAndOrderFront(nil)
            return
        }
        returnApp = target.app?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? returnApp : target.app
        session.begin(text: text, source: target.name, locale: locale)
        show(near: target.windowFrame)
    }

    /// Opens an empty window from the menu, for typing an idea instead of saying it.
    func openEmpty(locale: String) {
        if isVisible {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        returnApp = NSWorkspace.shared.frontmostApplication
        session.begin(text: "", source: "", locale: locale)
        show(near: nil)
    }

    func close() { window?.close() }

    /// Copies the draft, closes the window, and brings back the app the person was working in.
    func copyAndReturn() {
        session.copy()
        let app = returnApp
        window?.close()
        if let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            app.activate()
        }
    }

    var returnAppName: String? {
        guard let returnApp, returnApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return returnApp.localizedName
    }

    private func show(near anchor: NSRect?) {
        let window = window ?? makeWindow()
        let reference = anchor.map { NSPoint(x: $0.midX, y: $0.midY) } ?? NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(reference) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            let width = min(size.width, visible.width - 24)
            let height = min(size.height, visible.height - 24)
            window.setFrame(NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2,
                                   width: width, height: height), display: true)
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Refine with Voxley"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: RefineView(
            session: session,
            returnAppName: { [weak self] in self?.returnAppName },
            copyAndReturn: { [weak self] in self?.copyAndReturn() },
            close: { [weak self] in self?.close() }
        ))
        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        session.end()
    }
}

struct RefineView: View {
    @Bindable var session: RefineSession
    let returnAppName: () -> String?
    let copyAndReturn: () -> Void
    let close: () -> Void
    @FocusState private var focus: Field?

    private enum Field { case draft, request }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            draftEditor
            conversation
            requestRow
            actions
        }
        .padding(.horizontal, 18)
        .padding(.top, 34)
        .padding(.bottom, 16)
        .frame(minWidth: 380, minHeight: 440)
        .background(.regularMaterial)
        .tint(.voxleyAccent)
        .onAppear { focus = .draft }
        .onExitCommand(perform: close)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.voxleyAccent)
                .accessibilityHidden(true)
            Text("Refine your idea").font(.headline)
            Spacer()
            if !session.sourceName.isEmpty {
                Text("from \(session.sourceName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var draftEditor: some View {
        TextEditor(text: $session.draft)
            .font(.body)
            .focused($focus, equals: .draft)
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: 150)
            .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary).allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                if session.draft.isEmpty {
                    Text("Type or dictate your idea…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .disabled(session.isThinking)
            .accessibilityLabel("Draft")
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if session.messages.isEmpty {
                        Text("Edit the draft yourself, or press Refine and tell Apple Intelligence what to change. It runs on your Mac.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.messages) { message in
                        RefineBubble(message: message).id(message.id)
                    }
                    if session.isThinking {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Apple Intelligence is refining…").font(.callout).foregroundStyle(.secondary)
                        }
                        .id("thinking")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 70, maxHeight: 150)
            .onChange(of: session.messages.count) {
                withAnimation { proxy.scrollTo(session.messages.last?.id, anchor: .bottom) }
            }
        }
    }

    private var requestRow: some View {
        HStack(spacing: 8) {
            TextField("Ask for a change, like “make it shorter”", text: $session.request)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .request)
                .onSubmit { session.refine() }
                .disabled(session.isThinking)
            Button {
                session.refine()
            } label: {
                Label("Refine", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!session.canRefine)
            .help(session.modelReady ? "Refine the draft with Apple Intelligence" : session.modelStatus)
        }
    }

    private var actions: some View {
        HStack {
            Button("Undo", systemImage: "arrow.uturn.backward") { session.undo() }
                .disabled(session.previousDrafts.isEmpty || session.isThinking)
            Spacer()
            if session.copied {
                Label("Copied", systemImage: "checkmark")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button("Copy") { session.copy() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(session.draft.isEmpty)
            Button(returnAppName().map { "Copy and Return to \($0)" } ?? "Copy and Close", action: copyAndReturn)
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(session.draft.isEmpty)
        }
    }
}

private struct RefineBubble: View {
    let message: RefineMessage

    var body: some View {
        switch message.role {
        case .person:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.voxleyAccent.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
                    .textSelection(.enabled)
            }
        case .assistant:
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "apple.intelligence")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Apple Intelligence")
                Text(message.text)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                    .textSelection(.enabled)
                Spacer(minLength: 40)
            }
        case .note:
            Label(message.text, systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
