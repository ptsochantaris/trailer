
class CenterTextField: NSTextField {

    var vibrant = true

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		bezeled = false
		editable = false
		selectable = false
		drawsBackground = false
		(cell as! CenterTextFieldCell).scrollable = false
	}

	required init?(coder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}

	override class func initialize() {
		setCellClass(CenterTextFieldCell)
	}

    override var allowsVibrancy: Bool {
		return vibrant
	}

}
