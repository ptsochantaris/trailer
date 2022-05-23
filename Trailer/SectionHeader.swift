import Cocoa

final class SectionHeader: NSTableRowView {

	var titleView: CenterTextField!

	init(title: String, showRemoveAllButton: Bool) {

		let titleHeight: CGFloat = 42

		super.init(frame: CGRect(x: 0, y: 0, width: MENU_WIDTH, height: titleHeight))

		let W = MENU_WIDTH - app.scrollBarWidth
		if showRemoveAllButton {
			let buttonRect = CGRect(x: W-100, y: 5, width: 90, height: titleHeight)
			let unpin = NSButton(frame: buttonRect)
			unpin.title = "Remove All"
			unpin.target = self
			unpin.action = #selector(unPinSelected)
			unpin.setButtonType(.momentaryLight)
			unpin.bezelStyle = .roundRect
			unpin.font = NSFont.systemFont(ofSize: 10)
			addSubview(unpin)
		}

		let x = W-120-AVATAR_SIZE-LEFTPADDING
		titleView = CenterTextField(frame: CGRect(x: 12, y: 4, width: x, height: titleHeight))
		titleView.attributedStringValue = NSAttributedString(string: title, attributes: [
			NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: 14),
			NSAttributedString.Key.foregroundColor: NSColor.secondaryLabelColor])
		addSubview(titleView)
	}

	@objc private func unPinSelected() {
		app.removeSelected(on: titleView.attributedStringValue.string)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}
