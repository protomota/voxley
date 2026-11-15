import AppKit
import SwiftUI

extension Color {
    static var voxleyAccent: Color {
        Color(nsColor: NSColor(named: "AccentColor") ?? .systemYellow)
    }
}
