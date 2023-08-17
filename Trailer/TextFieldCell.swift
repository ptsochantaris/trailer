import Cocoa

private final class TextFieldCellTextView: NSTextView, NSTextViewDelegate {
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags
        if modifiers.contains(.command), let textView = window?.firstResponder as? NSTextView {
            let range = textView.selectedRange()
            let selected = range.length > 0
            let keyCode = event.keyCode

            if keyCode == 6 { // command + Z
                if let undoManager = textView.undoManager {
                    if modifiers.contains(.shift) {
                        if undoManager.canRedo {
                            undoManager.redo()
                            return
                        }
                    } else {
                        if undoManager.canUndo {
                            undoManager.undo()
                            return
                        }
                    }
                }
            } else if keyCode == 7, selected { // command + X
                textView.cut(self)
                return

            } else if keyCode == 8, selected { // command + C
                textView.copy(self)
                return

            } else if keyCode == 9 { // command + V
                textView.paste(self)
                return
            }
        }

        super.keyDown(with: event)
    }

    override func insertNewline(_: Any?) {
        window?.makeFirstResponder(nextResponder)
    }

    var originalText: String?
    override func cancelOperation(_: Any?) {
        if let originalText {
            string = originalText
        }
        window?.makeFirstResponder(nextResponder)
    }

    override func viewDidMoveToSuperview() {
        if superview != nil {
            originalText = textContainer?.textView?.string
        }
    }
}

final class TextFieldCell: NSTextFieldCell {
    private lazy var tfctv = TextFieldCellTextView()

    override func fieldEditor(for _: NSView) -> NSTextView? {
        tfctv
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        rect.offsetBy(dx: 0, dy: 3)
    }
}
