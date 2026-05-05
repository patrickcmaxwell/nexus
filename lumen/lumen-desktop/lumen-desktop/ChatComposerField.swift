import SwiftUI
import AppKit

/// AppKit-backed multi-line composer with chat-app submit semantics:
///
/// - **Return** submits (calls `onSubmit`)
/// - **Shift+Return / Option+Return / Cmd+Return** insert a newline
/// - Standard mac editing shortcuts (⌘A, ⌘C, ⌘V, ⌘Z, etc.) all work
/// - Pasting preserves text (rich-paste falls back to plain)
/// - Auto-grows up to `maxHeight`; scrolls past that
/// - Renders a placeholder when empty
///
/// Why custom: SwiftUI's `TextField(axis: .vertical)` triggers `onSubmit` on
/// every Return with no way to override, so Director-style "type a paragraph"
/// editing didn't work. Wrapping `NSTextView` is the cleanest path to the
/// Slack/Discord composer behavior the Director asked for.
struct ChatComposerField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var minHeight: CGFloat = 22
    var maxHeight: CGFloat = 140
    var fontSize: CGFloat  = 14
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> ComposerScrollView {
        let scroll = ComposerScrollView()
        scroll.hasVerticalScroller   = true
        scroll.hasHorizontalScroller = false
        scroll.borderType            = .noBorder
        scroll.drawsBackground       = false
        scroll.autohidesScrollers    = true
        scroll.maxHeight             = maxHeight
        scroll.minHeight             = minHeight

        let tv = ComposerTextView()
        tv.delegate                       = context.coordinator
        tv.coordinator                    = context.coordinator
        tv.allowsUndo                     = true
        tv.isRichText                     = false
        tv.importsGraphics                = false
        tv.font                           = .systemFont(ofSize: fontSize)
        tv.textColor                      = .labelColor
        tv.insertionPointColor            = NSColor.controlAccentColor
        tv.backgroundColor                = .clear
        tv.drawsBackground                = false
        tv.textContainerInset             = NSSize(width: 0, height: 4)
        tv.isVerticallyResizable          = true
        tv.isHorizontallyResizable        = false
        tv.autoresizingMask               = [.width]
        tv.minSize                        = NSSize(width: 0, height: minHeight)
        tv.maxSize                        = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = 0
        tv.string                         = text
        tv.placeholderString              = placeholder

        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ scroll: ComposerScrollView, context: Context) {
        guard let tv = scroll.documentView as? ComposerTextView else { return }
        // Push external text changes (e.g. composer cleared after submit) into
        // the NSTextView without disturbing an in-flight selection.
        if tv.string != text {
            let selected = tv.selectedRange()
            tv.string = text
            tv.setSelectedRange(NSRange(location: min(selected.location, text.count), length: 0))
            tv.needsDisplay = true
        }
        if tv.placeholderString != placeholder {
            tv.placeholderString = placeholder
            tv.needsDisplay = true
        }
        scroll.maxHeight = maxHeight
        scroll.minHeight = minHeight
        scroll.invalidateIntrinsicContentSize()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatComposerField
        init(_ p: ChatComposerField) { parent = p }

        func textDidChange(_ note: Notification) {
            guard let tv = note.object as? NSTextView else { return }
            parent.text = tv.string
            (tv.enclosingScrollView as? ComposerScrollView)?.invalidateIntrinsicContentSize()
        }

        func submit() { parent.onSubmit() }
    }
}

/// NSTextView subclass that intercepts Return to drive submit semantics and
/// paints a placeholder string when empty. Plain Return → coordinator.submit;
/// modified Return → fall through to default newline insertion.
final class ComposerTextView: NSTextView {
    weak var coordinator: ChatComposerField.Coordinator?
    var placeholderString: String = "" {
        didSet { needsDisplay = true }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { // Return
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let modified = !mods.isDisjoint(with: [.shift, .option, .command])
            if !modified {
                coordinator?.submit()
                return
            }
            // Modifier held — insert a real newline like a normal text view.
            insertNewlineIgnoringFieldEditor(self)
            return
        }
        super.keyDown(with: event)
    }

    /// Force plain-text paste so pasting from web/Slack doesn't drag in fonts
    /// or styles that look out of place in the composer.
    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: self.font ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.placeholderTextColor
        ]
        let inset = self.textContainerInset
        let pt = NSPoint(x: inset.width, y: inset.height)
        (placeholderString as NSString).draw(at: pt, withAttributes: attrs)
    }
}

/// NSScrollView that reports an intrinsic height equal to its document's
/// laid-out height (clamped to [minHeight, maxHeight]) so SwiftUI's layout
/// can grow the composer as the Director types.
final class ComposerScrollView: NSScrollView {
    var minHeight: CGFloat = 22
    var maxHeight: CGFloat = 140

    override var intrinsicContentSize: NSSize {
        guard let tv = documentView as? NSTextView,
              let lm = tv.layoutManager,
              let tc = tv.textContainer else {
            return NSSize(width: NSView.noIntrinsicMetric, height: minHeight)
        }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc).height + tv.textContainerInset.height * 2
        let h = max(minHeight, min(maxHeight, used))
        return NSSize(width: NSView.noIntrinsicMetric, height: h)
    }
}
