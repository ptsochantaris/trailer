
extension NSTextField {
	@objc final func trailerUndo() {
		currentEditor()?.undoManager?.undo()
	}
	@objc final func trailerRedo() {
		currentEditor()?.undoManager?.redo()
	}
	@objc final func trailerCopy() {
		currentEditor()?.copy(nil)
	}
	@objc final func trailerPaste() {
		currentEditor()?.paste(nil)
	}
	@objc final func trailerCut() {
		currentEditor()?.cut(nil)
	}
}

final class Application: NSApplication {
	override func sendEvent(_ event: NSEvent) {
		if event.type == .keyDown {
			let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
			if modifiers == .command {
				if let char = event.charactersIgnoringModifiers {
					switch char {
					case "x": if sendAction(#selector(NSTextField.trailerCut), to: nil, from: self) { return }
					case "v": if sendAction(#selector(NSTextField.trailerPaste), to: nil, from: self) { return }
					case "z": if sendAction(#selector(NSTextField.trailerUndo), to: nil, from: self) { return }
					case "c":
						if let url = app.focusedItem(blink: true)?.webUrl {
							let p = NSPasteboard.general
							p.clearContents()
							p.setString(url, forType: NSPasteboard.PasteboardType.string)
							return

						} else {
							if sendAction(#selector(NSTextField.trailerCopy), to: nil, from: self) { return }
						}
					case "a":
						if let i = app.focusedItem(blink: true) {
							if i.hasUnreadCommentsOrAlert {
								i.catchUpWithComments()
							} else {
								i.latestReadCommentDate = .distantPast
								i.postProcess()
							}
							DataManager.saveDB()
							app.updateRelatedMenus(for: i)
							return
						} else if sendAction(#selector(NSResponder.selectAll), to: nil, from: self) {
							return
						}
					default: break
					}
				}
			} else if modifiers == [.command, .shift] {
				if let char = event.charactersIgnoringModifiers {
					if char == "Z" && sendAction(#selector(NSTextField.trailerRedo), to: nil, from: self) { return }
				}
			}
		}
		super.sendEvent(event)
	}
}
