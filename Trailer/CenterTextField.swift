
class CenterTextField: NSTextField {

    var vibrant = true

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		isBezeled = false
		isEditable = false
		isSelectable = false
		drawsBackground = false
		(cell as! CenterTextFieldCell).isScrollable = false
	}

	required init?(coder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}

	override class func initialize() {
		setCellClass(CenterTextFieldCell.self)
	}

    override var allowsVibrancy: Bool {
		return vibrant
	}

}
