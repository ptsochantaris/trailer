
class CenterTextField: NSTextField {

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		self.bezeled = false
		self.editable = false
		self.selectable = false
		self.drawsBackground = false
		if let myCell = self.cell() as? CenterTextFieldCell {
			myCell.scrollable = false
		}
	}

	required init?(coder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}

	override class func initialize() {
		self.setCellClass(CenterTextFieldCell)
	}

}
