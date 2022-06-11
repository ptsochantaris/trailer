import Cocoa

final class MessageView: NSView {
    init(frame frameRect: NSRect, message: NSAttributedString) {
        super.init(frame: frameRect)
        let messageRect = bounds.insetBy(dx: MENU_WIDTH * 0.13, dy: 0)
        let messageField = CenterTextField(frame: messageRect)
        messageField.autoresizingMask = [.height, .width]
        messageField.attributedStringValue = message
        addSubview(messageField)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
