
final class MessageView: NSView {

	init(frame frameRect: NSRect, message: NSAttributedString) {
		super.init(frame: frameRect)
		let messageRect = bounds.insetBy(dx: MENU_WIDTH*0.13, dy: 0)
		let messageField = CenterTextField(frame: messageRect)
		messageField.autoresizingMask = [.height, .width]
		messageField.attributedStringValue = message
		addSubview(messageField)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

}
