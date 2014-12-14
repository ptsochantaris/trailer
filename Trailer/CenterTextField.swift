
class CenterTextField: NSTextField {

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		bezeled = false
		editable = false
		selectable = false
		drawsBackground = false
		if let myCell = cell() as? CenterTextFieldCell {
			myCell.scrollable = false
		}
	}

	required init?(coder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}

	override class func initialize() {
		setCellClass(CenterTextFieldCell)
	}

}
