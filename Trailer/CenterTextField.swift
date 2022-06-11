import Cocoa

class CenterTextField: NSTextField {
    var vibrant = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBezeled = false
        isEnabled = false
        isEditable = false
        isSelectable = false
        drawsBackground = false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var allowsVibrancy: Bool {
        vibrant
    }
}
