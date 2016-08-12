
final class LinkField: CenterTextField {

	var targetUrl: String?
	var needsCommand = false

	var highlight = false
	var normalColor: NSColor?

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		let check = attributedStringValue .boundingRect(with: bounds.size,
			options: stringDrawingOptions)

		let newArea = NSTrackingArea(rect: check,
			options: [NSTrackingAreaOptions.mouseEnteredAndExited, NSTrackingAreaOptions.mouseMoved, NSTrackingAreaOptions.activeInKeyWindow],
			owner: self,
			userInfo: nil)

		addTrackingArea(newArea)

		if let point = window?.mouseLocationOutsideOfEventStream, NSPointInRect(point, check) {
			mouseEntered(with: NSEvent())
		}
	}

	override func resetCursorRects() {
		super.resetCursorRects()
		if highlight {

			let check = attributedStringValue.boundingRect(with: bounds.size,
				options: stringDrawingOptions)
			addCursorRect(check, cursor: NSCursor.pointingHand())
		}
	}

	override func mouseExited(with theEvent: NSEvent) {
		highlight = false
		if targetUrl != nil {
			textColor = normalColor
			window?.invalidateCursorRects(for: self)
		}
	}

	override func mouseEntered(with theEvent: NSEvent) {
		normalColor = textColor
		checkMove(from: theEvent)
	}

	override func mouseMoved(with theEvent: NSEvent) {
		checkMove(from: theEvent)
	}

	private func checkMove(from theEvent: NSEvent) {
		if targetUrl != nil {
			if highlight {
				if needsCommand && !theEvent.modifierFlags.contains(.command) {
					highlight = false
					textColor = normalColor
					window?.invalidateCursorRects(for: self)
				}
			} else {
				if !needsCommand || theEvent.modifierFlags.contains(.command) {
					highlight = true
					textColor = NSColor.blue
					window?.invalidateCursorRects(for: self)
				}
			}
		}
	}

	override func mouseDown(with theEvent: NSEvent) { }

	override func mouseUp(with theEvent: NSEvent) {
		if targetUrl == nil {
            selectParentPr(from: theEvent)
		} else {
			if needsCommand {
				if theEvent.modifierFlags.contains(.command) {
					if theEvent.modifierFlags.contains(.option) {
						app.ignoreNextFocusLoss = true
					}
					mouseExited(with: theEvent)
					NSWorkspace.shared().open(URL(string: targetUrl!)!)
				} else {
                    selectParentPr(from: theEvent)
				}
			} else {
				mouseExited(with: theEvent)
				NSWorkspace.shared().open(URL(string: targetUrl!)!)
			}
		}
	}

    private func selectParentPr(from theEvent: NSEvent) {
        if let parentView = nextResponder as? TrailerCell, let pr = parentView.associatedDataItem {
            let isAlternative = theEvent.modifierFlags.contains(.option)
			app.selected(pr, alternativeSelect: isAlternative, window: window)
        }
    }

}
