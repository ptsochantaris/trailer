
final class PrTable: NSTableView, NSPasteboardItemDataProvider {

	func cell(at theEvent: NSEvent) -> NSView? {
		let globalLocation = theEvent.locationInWindow
		let localLocation = convert(globalLocation, from: nil)
		return view(atColumn: column(at: localLocation), row: row(at: localLocation), makeIfNecessary: false)
	}

	override func mouseDown(with theEvent: NSEvent) {
		dragOrigin = nil
	}

	override func mouseUp(with theEvent: NSEvent) {
		if let prView = cell(at: theEvent) as? TrailerCell, let item = prView.associatedDataItem {
			let isAlternative = ((theEvent.modifierFlags.intersection(.option)) == .option)
			app.selected(item, alternativeSelect: isAlternative, window: window)
		}
	}

	func scale(image: NSImage, toFillSize: CGSize) -> NSImage {
		let targetFrame = NSMakeRect(0, 0, toFillSize.width, toFillSize.height)
		let sourceImageRep = image.bestRepresentation(for: targetFrame, context: nil, hints: nil)
		let targetImage = NSImage(size: toFillSize)
		targetImage.lockFocus()
		sourceImageRep!.draw(in: targetFrame)
		targetImage.unlockFocus()
		return targetImage
	}

	private var dragOrigin: NSEvent?
	override func mouseDragged(with theEvent: NSEvent) {

		if let origin = dragOrigin {

			func fastDistance(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
				let dx = fabs(a)
				let dy = fabs(b)
				return (dx < dy) ? dy + 0.337 * dx : dx + 0.337 * dy
			}

			let l = theEvent.locationInWindow
			let o = origin.locationInWindow
			if fastDistance(o.y - l.y, o.x - l.x) < 15 {
				return
			}
		} else {
			dragOrigin = theEvent
			return
		}

		draggingUrl = nil

		if let prView = cell(at: dragOrigin!) as? TrailerCell, let url = prView.associatedDataItem?.webUrl {

			draggingUrl = url

			let dragIcon = scale(image: NSApp.applicationIconImage, toFillSize: CGSize(width: 32, height: 32))
			let pbItem = NSPasteboardItem()
			pbItem.setDataProvider(self, forTypes: [NSPasteboardTypeString])
			let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
			var dragPosition = convert(theEvent.locationInWindow, from: nil)
			dragPosition.x -= 17
			dragPosition.y -= 17
			dragItem.setDraggingFrame(NSMakeRect(dragPosition.x, dragPosition.y, dragIcon.size.width, dragIcon.size.height), contents: dragIcon)

			let draggingSession = beginDraggingSession(with: [dragItem], event: theEvent, source: self)
			draggingSession.animatesToStartingPositionsOnCancelOrFail = true
		}
	}

	override func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
		return (context == .outsideApplication) ?  .copy : NSDragOperation()
	}

	private var draggingUrl: String?
	func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: String) {
		if let pasteboard = pasteboard, type.compare(NSPasteboardTypeString) == .orderedSame && draggingUrl != nil {
			pasteboard.setData(draggingUrl!.data(using: String.Encoding.utf8)!, forType: NSPasteboardTypeString)
			draggingUrl = nil
		}
	}

	override func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
		return true
	}

	override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
		return true
	}
}
