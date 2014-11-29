import Cocoa

class Application: NSApplication {
	override func sendEvent(theEvent: NSEvent) {
		if theEvent.type == NSEventType.KeyDown {
			let modifiers = theEvent.modifierFlags & NSEventModifierFlags.DeviceIndependentModifierFlagsMask
			if modifiers == NSEventModifierFlags.CommandKeyMask {
				if let char = theEvent.charactersIgnoringModifiers {
					switch char {
					case "x": if self.sendAction(Selector("cut:"), to:nil, from:self) { return }
					case "v": if self.sendAction(Selector("paste:"), to:nil, from:self) { return }
					case "z": if self.sendAction(Selector("undo:"), to:nil, from:self) { return }
					case "a": if self.sendAction(Selector("selectAll:"), to:nil, from:self) { return }
					case "c":
						if let url = app.focusedItemUrl() {
							let p = NSPasteboard.generalPasteboard()
							p.clearContents()
							p.setString(url, forType:NSStringPboardType)
							return
						} else {
							if self.sendAction(Selector("copy:"), to:nil, from:self) { return }
						}
					default: break
					}
				}
			} else if modifiers == NSEventModifierFlags.CommandKeyMask | NSEventModifierFlags.ShiftKeyMask {
				if let char = theEvent.charactersIgnoringModifiers {
					if char == "Z" && self.sendAction(Selector("redo:"), to:nil, from:self) { return }
				}
			}
		}
		super.sendEvent(theEvent);
	}
}
