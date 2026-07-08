import Cocoa

/// Spec 04 — paste via clipboard + synthetic ⌘V, then restore the
/// previous clipboard. Known accepted race: anything the user copies
/// during the restore window is clobbered.
enum Paster {
    static let restoreDelay: TimeInterval = 1.0
    private static let vKey: CGKeyCode = 9 // kVK_ANSI_V

    static var frontmostAppBundleID: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotItems(of: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Give the pasteboard a beat to settle before the target app reads it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            sendCmdV()
            DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                restore(snapshot, to: pasteboard)
            }
        }
    }

    private static func sendCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            dlog("paste: could not create ⌘V events")
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        dlog("paste: ⌘V sent")
    }

    private static func snapshotItems(of pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy[type] = data
                }
            }
            return copy
        }
    }

    private static func restore(_ snapshot: [[NSPasteboard.PasteboardType: Data]],
                                to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        let items = snapshot.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
        dlog("paste: previous clipboard restored (\(items.count) item(s))")
    }
}
