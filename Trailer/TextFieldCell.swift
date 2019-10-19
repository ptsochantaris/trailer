
private final class TextFieldCellTextView: NSTextView, NSTextViewDelegate {
	override func keyDown(with event: NSEvent) {
		let modifiers = event.modifierFlags
		if modifiers.contains(.command), let textView = window?.firstResponder as? NSTextView {

			let range = textView.selectedRange()
			let selected = range.length > 0
			let keyCode = event.keyCode

			if keyCode == 6 { //command + Z
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
			} else if keyCode == 7 && selected { // command + X
				textView.cut(self)
				return

			} else if keyCode == 8 && selected { // command + C
				textView.copy(self)
				return

			} else if keyCode == 9 { // command + V
				textView.paste(self)
				return
			}
            
        }

		super.keyDown(with: event)
	}
    
    override func insertNewline(_ sender: Any?) {
        window?.makeFirstResponder(nextResponder)
    }
    
    var originalText: String?
    override func cancelOperation(_ sender: Any?) {
        if let o = originalText {
            self.string = o
        }
        window?.makeFirstResponder(nextResponder)
    }
}

final class TextFieldCell: NSTextFieldCell {
	override func fieldEditor(for controlView: NSView) -> NSTextView? {
		let v = TextFieldCellTextView()
        DispatchQueue.main.async {
            v.originalText = self.stringValue
        }
        return v
	}
}
