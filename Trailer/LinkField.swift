
class LinkField: CenterTextField {

	var targetUrl: String?
	var needsCommand: Bool = false

	var highlight: Bool = false
	var normalColor: NSColor?

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		let check = self.attributedStringValue .boundingRectWithSize(self.bounds.size,
			options: NSStringDrawingOptions.UsesLineFragmentOrigin | NSStringDrawingOptions.UsesFontLeading)

		let newArea = NSTrackingArea(rect: check,
			options: NSTrackingAreaOptions.MouseEnteredAndExited | NSTrackingAreaOptions.MouseMoved | NSTrackingAreaOptions.ActiveInKeyWindow,
			owner: self,
			userInfo: nil)

		self.addTrackingArea(newArea)

		if let point = self.window?.mouseLocationOutsideOfEventStream {
			if NSPointInRect(point, check) {
				self.mouseEntered(NSEvent())
			}
		}
	}

	override func resetCursorRects() {
		super.resetCursorRects()
		if highlight {

			let check = self.attributedStringValue .boundingRectWithSize(self.bounds.size,
				options: NSStringDrawingOptions.UsesLineFragmentOrigin | NSStringDrawingOptions.UsesFontLeading)
			self.addCursorRect(check, cursor: NSCursor.pointingHandCursor())
		}
	}

	override func mouseExited(theEvent: NSEvent) {
		highlight = false
		if self.targetUrl != nil {
			self.textColor = normalColor
			self.window?.invalidateCursorRectsForView(self)
		}
	}

	override func mouseMoved(theEvent: NSEvent) {
		if self.targetUrl != nil {
			if(highlight) {
				if self.needsCommand && (theEvent.modifierFlags & NSEventModifierFlags.CommandKeyMask != NSEventModifierFlags.CommandKeyMask) {
					highlight = false
					self.textColor = normalColor
					self.window?.invalidateCursorRectsForView(self)
				}
			} else {
				if !self.needsCommand || (theEvent.modifierFlags & NSEventModifierFlags.CommandKeyMask == NSEventModifierFlags.CommandKeyMask) {
					highlight = true
					normalColor = self.textColor
					self.textColor = NSColor.blueColor()
					self.window?.invalidateCursorRectsForView(self)
				}
			}
		}
	}

	override func mouseDown(theEvent: NSEvent) {
		if self.targetUrl == nil {
			self.nextResponder?.mouseDown(theEvent)
		} else {
			if self.needsCommand {
				if theEvent.modifierFlags & NSEventModifierFlags.CommandKeyMask == NSEventModifierFlags.CommandKeyMask {
					if theEvent.modifierFlags & NSEventModifierFlags.AlternateKeyMask == NSEventModifierFlags.AlternateKeyMask {
						app.ignoreNextFocusLoss = true
					}
					NSWorkspace.sharedWorkspace().openURL(NSURL(string:self.targetUrl!)!)
					self.mouseExited(theEvent)
				} else {
					self.nextResponder?.mouseDown(theEvent)
				}
			} else {
				NSWorkspace.sharedWorkspace().openURL(NSURL(string:self.targetUrl!)!)
				self.mouseExited(theEvent)
			}
		}
	}

}
