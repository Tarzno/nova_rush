import Carbon

/// Names of the position-based keys on the current keyboard layout, for the
/// on-table hint and Help. The nudge keys are read by position — the bottom
/// row's left, middle and right keys — so their labels depend on the layout:
/// Z N / on a US keyboard, Y N - on a German one.
enum KeyLabels {
    static let nudgeKeyCodes: [UInt16] = [6, 45, 44]       // from the left, front, from the right
    private static let usNudgeLabels = ["Z", "N", "/"]

    /// Labels of the three nudge keys (US labels where a key can't be named).
    static var nudge: [String] {
        zip(nudgeKeyCodes, usNudgeLabels).map { label(forKeyCode: $0) ?? $1 }
    }

    /// The character a key types on the current (ASCII-capable) layout,
    /// upper-cased; nil if it types nothing printable.
    static func label(forKeyCode keyCode: UInt16) -> String? {
        let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys,
                           chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: chars, count: length)
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return text.isEmpty ? nil : text
    }
}
