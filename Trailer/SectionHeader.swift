
class SectionHeader: NSTableRowView {

	let titleView: CenterTextField!

	init(title: String, showRemoveAllButton: Bool) {

		let menuWidth = CGFloat(MENU_WIDTH)
		let titleHeight = CGFloat(TITLE_HEIGHT)

		super.init(frame: NSMakeRect(0, 0, menuWidth, titleHeight))

		canDrawSubviewsIntoLayer = true

		let W = menuWidth - CGFloat(app.scrollBarWidth)
		if showRemoveAllButton {
			let buttonRect = NSMakeRect(W-100, 5, 90, titleHeight)
			let unpin = NSButton(frame: buttonRect)
			unpin.title = "Remove All"
			unpin.target = self
			unpin.action = Selector("unPinSelected")
			unpin.setButtonType(NSButtonType.MomentaryLightButton)
			unpin.bezelStyle = NSBezelStyle.RoundRectBezelStyle
			unpin.font = NSFont.systemFontOfSize(10)
			addSubview(unpin)
		}

		let x = W-120-CGFloat(AVATAR_SIZE-LEFTPADDING)
		titleView = CenterTextField(frame: NSMakeRect(12, 4, x, titleHeight))
		titleView.attributedStringValue = NSAttributedString(string: title, attributes: [
				NSFontAttributeName: NSFont.boldSystemFontOfSize(14),
				NSForegroundColorAttributeName: NSColor.controlShadowColor()])
		addSubview(titleView)

		let offset = (MenuWindow.usingVibrancy() ? 2.5 : 3.5) as CGFloat
		let dividerView = NSView(frame: CGRectMake(1.0, offset, menuWidth-2, 0.5))
		dividerView.wantsLayer = true
		dividerView.layer?.backgroundColor = NSColor.controlShadowColor().CGColor
		addSubview(dividerView)
	}

	func unPinSelected() {
		app.sectionHeaderRemoveSelected(titleView.attributedStringValue.string)
	}

	required init?(coder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}
}
