import AppKit

/// The license Nova Rush is published under. Must stay identical to the
/// LICENSE file in the repository root — Scripts/build-app.sh compares the two
/// (via `--license`) and refuses to build a bundle if they differ.
enum License {
    static let text = """
        MIT License

        Copyright (c) 2026 Hanno Teeling

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
        """

    /// Shown below the MIT text in the License window. Keep in line with
    /// LICENSE-ASSETS.
    static let assetsNote = "The MIT License above covers the source code. The music, the backdrop "
        + "artwork, the generated sound effects and the voice callouts are licensed "
        + "separately under Creative Commons Attribution-NonCommercial 4.0 (CC BY-NC 4.0): "
        + "you may share and adapt them for non-commercial purposes, with credit. "
        + "Recording and streaming gameplay — including monetized videos — is explicitly "
        + "allowed. See LICENSE-ASSETS for details."

    /// The text as paragraphs, with the file's hard line breaks removed so
    /// each paragraph wraps to whatever width the window has.
    static var paragraphs: [String] {
        text.components(separatedBy: "\n\n").map {
            $0.replacingOccurrences(of: "\n", with: " ")
        }
    }
}

/// Nova Rush → License: shows the license text in a scrollable, selectable,
/// read-only window (same layout as Polymandala's License window).
final class LicenseWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Nova Rush License"
        window.minSize = NSSize(width: 420, height: 300)
        window.isReleasedWhenClosed = false
        self.init(window: window)

        let scroll = NSScrollView(frame: window.contentLayoutRect)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true

        let textView = NSTextView(frame: scroll.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(Self.licenseText())

        scroll.documentView = textView
        window.contentView = scroll
        window.center()
    }

    /// The license laid out for the window.
    static func licenseText() -> NSAttributedString {
        let text = NSMutableAttributedString()
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 10
        style.lineSpacing = 2
        for (index, paragraph) in License.paragraphs.enumerated() {
            // The first paragraph is the license's name.
            let font = index == 0 ? NSFont.boldSystemFont(ofSize: 15) : NSFont.systemFont(ofSize: 13)
            text.append(NSAttributedString(string: paragraph + "\n", attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: style,
            ]))
        }
        // The assets are licensed separately (LICENSE-ASSETS) — shown as a
        // note below the MIT text, deliberately not part of `License.text`
        // (which must match the LICENSE file exactly).
        let note = NSMutableParagraphStyle()
        note.paragraphSpacingBefore = 14
        note.paragraphSpacing = 6
        note.lineSpacing = 2
        text.append(NSAttributedString(string: "Assets\n", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 15),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: note,
        ]))
        let body = NSMutableParagraphStyle()
        body.paragraphSpacing = 10
        body.lineSpacing = 2
        text.append(NSAttributedString(string: License.assetsNote, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: body,
        ]))
        return text
    }
}
