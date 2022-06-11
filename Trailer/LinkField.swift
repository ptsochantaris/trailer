import Cocoa

extension NSColor {
    var highlighted: NSColor {
        if app.theme == .light {
            return .controlAccentColor
        }
        guard let c = cgColor.components, c.count > 2 else {
            return self
        }
        let r = min(1, c[0] + 0.3)
        let g = min(1, c[1] + 0.3)
        let b = min(1, c[2] + 0.3)
        let cgColor = CGColor(red: r, green: g, blue: b, alpha: 1)
        return NSColor(cgColor: cgColor) ?? self
    }
}

final class LinkField: CenterTextField {
    var targetUrl: String?
    var needsCommand = false

    var highlight = false
    var normalColor: NSColor?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let check = attributedStringValue.boundingRect(with: bounds.size, options: stringDrawingOptions)

        let newArea = NSTrackingArea(rect: check,
                                     options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow],
                                     owner: self,
                                     userInfo: nil)

        addTrackingArea(newArea)

        if let point = window?.mouseLocationOutsideOfEventStream, check.contains(point) {
            mouseEntered(with: NSEvent())
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if highlight {
            let check = attributedStringValue.boundingRect(with: bounds.size, options: stringDrawingOptions)
            addCursorRect(check, cursor: NSCursor.pointingHand)
        }
    }

    override func mouseExited(with _: NSEvent) {
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
                if needsCommand, !theEvent.modifierFlags.contains(.command) {
                    highlight = false
                    textColor = normalColor
                    window?.invalidateCursorRects(for: self)
                }
            } else {
                if !needsCommand || theEvent.modifierFlags.contains(.command) {
                    highlight = true
                    textColor = normalColor?.highlighted
                    window?.invalidateCursorRects(for: self)
                }
            }
        }
    }

    override func mouseDown(with _: NSEvent) {}

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
                    openLink(URL(string: targetUrl!)!)
                } else {
                    selectParentPr(from: theEvent)
                }
            } else {
                mouseExited(with: theEvent)
                openLink(URL(string: targetUrl!)!)
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
