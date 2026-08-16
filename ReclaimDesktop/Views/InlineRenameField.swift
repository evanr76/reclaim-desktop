import SwiftUI
import AppKit

/// An AppKit-backed single-line editor for inline (Finder-style) rename.
///
/// SwiftUI's `TextField` + `@FocusState` inside a `Table` is unreliable here: the
/// field editor can keep first-responder status, leaving a "latched" cell whose
/// text stays selected while clicks stop registering. An `NSTextField` with a
/// delegate commits on end-editing (focus loss), Enter, and cancels on Esc — every
/// exit path is handled at the AppKit level, so the cell never gets stuck.
struct InlineRenameField: NSViewRepresentable {
    @Binding var text: String
    var onCommit: (String) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.onCommit = onCommit
        context.coordinator.onCancel = onCancel
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit, onCancel: onCancel)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onCommit: (String) -> Void
        var onCancel: () -> Void
        private var finished = false   // guards against a second exit path firing

        init(text: Binding<String>, onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
            _text = text
            self.onCommit = onCommit
            self.onCancel = onCancel
        }

        func controlTextDidChange(_ note: Notification) {
            if let field = note.object as? NSTextField { text = field.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                guard !finished else { return true }
                finished = true
                onCommit((control as? NSTextField)?.stringValue ?? text)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                guard !finished else { return true }
                finished = true
                onCancel()
                return true
            default:
                return false
            }
        }

        func controlTextDidEndEditing(_ note: Notification) {
            // Focus lost (e.g. clicked another row) — commit unless Enter/Esc already ran.
            guard !finished else { return }
            finished = true
            onCommit((note.object as? NSTextField)?.stringValue ?? text)
        }
    }
}
