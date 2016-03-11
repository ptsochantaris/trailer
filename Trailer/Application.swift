
final class Application: NSApplication {
	override func sendEvent(theEvent: NSEvent) {
		if theEvent.type == NSEventType.KeyDown {
			let modifiers = theEvent.modifierFlags.intersect(NSEventModifierFlags.DeviceIndependentModifierFlagsMask)
			if modifiers == NSEventModifierFlags.CommandKeyMask {
				if let char = theEvent.charactersIgnoringModifiers {
					switch char {
					case "x": if sendAction(Selector("cut:"), to:nil, from:self) { return }
					case "v": if sendAction(Selector("paste:"), to:nil, from:self) { return }
					case "z": if sendAction(Selector("undo:"), to:nil, from:self) { return }
					case "c":
						if let url = app.focusedItem()?.webUrl {
							let p = NSPasteboard.generalPasteboard()
							p.clearContents()
							p.setString(url, forType:NSStringPboardType)
							return
						} else {
							if sendAction(Selector("copy:"), to:nil, from:self) { return }
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
						} else if sendAction(Selector("selectAll:"), to:nil, from:self) {
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
					if char == "Z" && sendAction(Selector("redo:"), to:nil, from:self) { return }
				}
			}
		}
		super.sendEvent(theEvent)
	}
}
