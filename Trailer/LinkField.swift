
class LinkField: CenterTextField {

	var targetUrl: String?
	var needsCommand: Bool = false

	var highlight: Bool = false
	var normalColor: NSColor?

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		let check = attributedStringValue .boundingRectWithSize(bounds.size,
			options: NSStringDrawingOptions.UsesLineFragmentOrigin | NSStringDrawingOptions.UsesFontLeading)

		let newArea = NSTrackingArea(rect: check,
			options: NSTrackingAreaOptions.MouseEnteredAndExited | NSTrackingAreaOptions.MouseMoved | NSTrackingAreaOptions.ActiveInKeyWindow,
			owner: self,
			userInfo: nil)

		addTrackingArea(newArea)

		if let point = window?.mouseLocationOutsideOfEventStream {
			if NSPointInRect(point, check) {
				mouseEntered(NSEvent())
			}
		}
	}

	override func resetCursorRects() {
		super.resetCursorRects()
		if highlight {

			let check = attributedStringValue .boundingRectWithSize(bounds.size,
				options: NSStringDrawingOptions.UsesLineFragmentOrigin | NSStringDrawingOptions.UsesFontLeading)
			addCursorRect(check, cursor: NSCursor.pointingHandCursor())
		}
	}

	override func mouseExited(theEvent: NSEvent) {
		highlight = false
		if targetUrl != nil {
			textColor = normalColor
			window?.invalidateCursorRectsForView(self)
		}
	}

	override func mouseEntered(theEvent: NSEvent) {
		normalColor = textColor
		checkMove(theEvent)
	}

	override func mouseMoved(theEvent: NSEvent) {
		checkMove(theEvent)
	}

	private func checkMove(theEvent: NSEvent) {
		if targetUrl != nil {
			if(highlight) {
				if needsCommand && (theEvent.modifierFlags & NSEventModifierFlags.CommandKeyMask != NSEventModifierFlags.CommandKeyMask) {
					highlight = false
					textColor = normalColor
					window?.invalidateCursorRectsForView(self)
				}
			} else {
				if !needsCommand || (theEvent.modifierFlags & NSEventModifierFlags.CommandKeyMask == NSEventModifierFlags.CommandKeyMask) {
					highlight = true
					textColor = NSColor.blueColor()
					window?.invalidateCursorRectsForView(self)
				}
			}
		}
	}

	override func mouseDown(theEvent: NSEvent) {
		if targetUrl == nil {
			nextResponder?.mouseDown(theEvent)
		} else {
			if needsCommand {
				if theEvent.modifierFlags & NSEventModifierFlags.CommandKeyMask == NSEventModifierFlags.CommandKeyMask {
					if theEvent.modifierFlags & NSEventModifierFlags.AlternateKeyMask == NSEventModifierFlags.AlternateKeyMask {
						app.ignoreNextFocusLoss = true
					}
					NSWorkspace.sharedWorkspace().openURL(NSURL(string:targetUrl!)!)
					mouseExited(theEvent)
				} else {
					nextResponder?.mouseDown(theEvent)
				}
			} else {
				NSWorkspace.sharedWorkspace().openURL(NSURL(string:targetUrl!)!)
				mouseExited(theEvent)
			}
		}
	}

}
