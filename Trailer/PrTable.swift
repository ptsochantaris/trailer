
final class PrTable: NSTableView, NSPasteboardItemDataProvider {

	func cellAtEvent(theEvent: NSEvent) -> NSView? {
		let globalLocation = theEvent.locationInWindow
		let localLocation = convertPoint(globalLocation, fromView:nil)
		return viewAtColumn(columnAtPoint(localLocation), row: rowAtPoint(localLocation), makeIfNecessary: false)
	}

	override func mouseDown(theEvent: NSEvent) { }

	override func mouseUp(theEvent: NSEvent) {
		if let prView = cellAtEvent(theEvent) as? TrailerCell {
			let isAlternative = ((theEvent.modifierFlags.intersect(NSEventModifierFlags.AlternateKeyMask)) == NSEventModifierFlags.AlternateKeyMask)
			app.dataItemSelected(prView.associatedDataItem(), alternativeSelect:isAlternative)
		}
	}

	func scaleImage(image: NSImage, toFillSize:CGSize) -> NSImage {
		let targetFrame = NSMakeRect(0, 0, toFillSize.width, toFillSize.height)
		let sourceImageRep = image.bestRepresentationForRect(targetFrame, context: nil, hints: nil)
		let targetImage = NSImage(size:toFillSize)
		targetImage.lockFocus()
		sourceImageRep!.drawInRect(targetFrame)
		targetImage.unlockFocus()
		return targetImage
	}

	override func mouseDragged(theEvent: NSEvent) {

		draggingUrl = nil

		if let prView = cellAtEvent(theEvent) as? TrailerCell {

			draggingUrl = prView.associatedDataItem().webUrl

			let dragIcon = scaleImage(NSApp.applicationIconImage, toFillSize: CGSizeMake(32, 32))
			let pbItem = NSPasteboardItem()
			pbItem.setDataProvider(self, forTypes: [NSPasteboardTypeString])
			let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
			var dragPosition = convertPoint(theEvent.locationInWindow, fromView: nil)
			dragPosition.x -= 17
			dragPosition.y -= 17
			dragItem.setDraggingFrame(NSMakeRect(dragPosition.x, dragPosition.y, dragIcon.size.width, dragIcon.size.height), contents: dragIcon)

			let draggingSession = beginDraggingSessionWithItems([dragItem], event: theEvent, source: self)
			draggingSession.animatesToStartingPositionsOnCancelOrFail = true
		}
	}

	override func draggingSession(session: NSDraggingSession, sourceOperationMaskForDraggingContext context: NSDraggingContext) -> NSDragOperation {
		return (context == NSDraggingContext.OutsideApplication) ?  NSDragOperation.Copy : NSDragOperation.None
	}

	private var draggingUrl: String?
	func pasteboard(pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: String) {
		if let pasteboard = pasteboard where type.compare(NSPasteboardTypeString) == NSComparisonResult.OrderedSame && draggingUrl != nil {
			pasteboard.setData(draggingUrl!.dataUsingEncoding(NSUTF8StringEncoding)!, forType: NSPasteboardTypeString)
			draggingUrl = nil
		}
	}

	override func ignoreModifierKeysForDraggingSession(session: NSDraggingSession) -> Bool {
		return true
	}

	override func validateProposedFirstResponder(responder: NSResponder, forEvent event: NSEvent?) -> Bool {
		return true
	}
}
