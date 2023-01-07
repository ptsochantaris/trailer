import Cocoa

final class AvatarView: NSImageView {
    init(frame frameRect: NSRect, url: String?) {
        super.init(frame: frameRect)

        guard let url else {
            let size = NSSize(width: AVATAR_SIZE, height: AVATAR_SIZE)
            let img = NSImage(size: size)
            img.lockFocus()
            NSColor.appTertiaryLabel.setFill()
            NSGraphicsContext.current?.cgContext.fill(NSRect(origin: .zero, size: size))
            img.unlockFocus()
            image = img
            return
        }

        imageAlignment = .alignCenter
        imageScaling = .scaleProportionallyUpOrDown

        let spinner = NSProgressIndicator(frame: bounds.insetBy(dx: 6, dy: 6))
        spinner.style = .spinning
        addSubview(spinner)
        spinner.startAnimation(self)

        Task {
            image = try? await HTTP.avatar(from: url).0
            spinner.stopAnimation(nil)
            spinner.removeFromSuperview()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = floor(AVATAR_SIZE / 2.0)
        let path = NSBezierPath(roundedRect: dirtyRect, xRadius: radius, yRadius: radius)
        path.setClip()
        super.draw(dirtyRect)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var allowsVibrancy: Bool {
        false
    }
}
