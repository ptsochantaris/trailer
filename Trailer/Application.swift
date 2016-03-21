
extension NSTextField {
	final func trailerUndo() {
		self.currentEditor()?.undoManager?.undo()
	}
	final func trailerRedo() {
		self.currentEditor()?.undoManager?.redo()
	}
}

final class Application: NSApplication {
	override func sendEvent(theEvent: NSEvent) {
		if theEvent.type == NSEventType.KeyDown {
			let modifiers = theEvent.modifierFlags.intersect(NSEventModifierFlags.DeviceIndependentModifierFlagsMask)
			if modifiers == NSEventModifierFlags.CommandKeyMask {
				if let char = theEvent.charactersIgnoringModifiers {
					switch char {
					case "x": if sendAction(#selector(NSText.cut(_:)), to:nil, from:self) { return }
					case "v": if sendAction(#selector(NSText.paste(_:)), to:nil, from:self) { return }
					case "z": if sendAction(#selector(NSTextField.trailerUndo), to:nil, from:self) { return }
					case "c":
						if let url = app.focusedItem()?.webUrl {
							let p = NSPasteboard.generalPasteboard()
							p.clearContents()
							p.setString(url, forType:NSStringPboardType)
							return
						} else {
							if sendAction(#selector(NSText.copy(_:)), to:nil, from:self) { return }
						}
					case "m":
						if let i = app.focusedItem() {
							i.muted = !(i.muted?.boolValue ?? false)
							i.postProcess()
							DataManager.saveDB()
							if i is PullRequest {
								app.updatePrMenu()
							} else {
								app.updateIssuesMenu()
							}
							return
						}
					case "a":
						if let i = app.focusedItem() {
							if i.unreadComments?.integerValue > 0 {
								i.catchUpWithComments()
							} else {
								i.latestReadCommentDate = never()
								i.postProcess()
							}
							DataManager.saveDB()
							if i is PullRequest {
								app.updatePrMenu()
							} else {
								app.updateIssuesMenu()
							}
							return
						} else if sendAction(#selector(NSResponder.selectAll(_:)), to:nil, from:self) {
							return
						}
					case "o":
						if let i = app.focusedItem(), w = i.repo.webUrl, u = NSURL(string: w) {
							NSWorkspace.sharedWorkspace().openURL(u)
							return
						}
					default: break
					}
				}
			} else if modifiers == NSEventModifierFlags.CommandKeyMask.union(NSEventModifierFlags.ShiftKeyMask) {
				if let char = theEvent.charactersIgnoringModifiers {
					if char == "Z" && sendAction(#selector(NSTextField.trailerRedo), to:nil, from:self) { return }
				}
			}
		}
		super.sendEvent(theEvent)
	}
}
