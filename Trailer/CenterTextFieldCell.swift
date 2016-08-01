
final class CenterTextFieldCell: NSTextFieldCell {
	override func drawingRect(forBounds theRect: NSRect) -> NSRect {
		var newRect = super.drawingRect(forBounds: theRect)
		let textSize = cellSize(forBounds: theRect)
		let heightDelta = newRect.size.height - textSize.height
		if heightDelta != 0 {
			newRect.size.height -= heightDelta
			newRect.origin.y += floor(heightDelta * 0.5)
		}
		return newRect
	}
}
