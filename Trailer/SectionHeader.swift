
final class SectionHeader: NSTableRowView {

	var titleView: CenterTextField!

	init(title: String, showRemoveAllButton: Bool) {

		super.init(frame: NSMakeRect(0, 0, MENU_WIDTH, TITLE_HEIGHT))

		let W = MENU_WIDTH - app.scrollBarWidth
		if showRemoveAllButton {
			let buttonRect = NSMakeRect(W-100, 5, 90, TITLE_HEIGHT)
			let unpin = NSButton(frame: buttonRect)
			unpin.title = "Remove All"
			unpin.target = self
			unpin.action = Selector("unPinSelected")
			unpin.setButtonType(NSButtonType.MomentaryLightButton)
			unpin.bezelStyle = NSBezelStyle.RoundRectBezelStyle
			unpin.font = NSFont.systemFontOfSize(10)
			addSubview(unpin)
		}

		let x = W-120-AVATAR_SIZE-LEFTPADDING
		titleView = CenterTextField(frame: NSMakeRect(12, 4, x, TITLE_HEIGHT))
		titleView.attributedStringValue = NSAttributedString(string: title, attributes: [
				NSFontAttributeName: NSFont.boldSystemFontOfSize(14),
				NSForegroundColorAttributeName: NSColor.controlShadowColor()])
		addSubview(titleView)
	}

	func unPinSelected() {
		app.sectionHeaderRemoveSelected(titleView.attributedStringValue.string)
	}

	required init?(coder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}
}
