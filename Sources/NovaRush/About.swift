import AppKit
import SwiftUI

/// Nova Rush → About Nova Rush: a custom About window in the style of the
/// Rosettica app (the standard About panel can't restyle its
/// name/version/copyright fonts). Text is deliberately a size larger than
/// the system panel's; the copyright (from Info.plist) is the smallest line.
struct AboutView: View {
    private var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "Copyright © 2026 Hanno Teeling. Code: MIT License · Assets: CC BY-NC 4.0"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
            Text("Nova Rush")
                .font(.system(size: 26, weight: .bold))
            Text("Version 1.0")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            VStack(spacing: 3) {
                Text("Concept: Hanno Teeling")
                Text("Initial implementation: Anthropic Claude Fable 5")
                Text("Refinement: Anthropic Claude Opus 5.5")
                Text("Music: Stable Audio 3; Backdrop: Z Image Turbo; Voices: Kokoro TTS")
            }
            .font(.system(size: 14))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            Text(copyright)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 28)
        .frame(width: 520)
        // The window adopts the content's full height, so no line is clipped.
        .fixedSize(horizontal: false, vertical: true)
    }
}

final class AboutWindowController: NSWindowController {
    convenience init() {
        let hosting = NSHostingView(rootView: AboutView())
        hosting.frame.size = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "About Nova Rush"
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.center()
        self.init(window: window)
    }
}
