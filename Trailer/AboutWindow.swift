
final class AboutWindow: NSWindow, NSWindowDelegate {

	@IBOutlet weak var version: NSTextField!

	@IBAction private func gitHubLinkSelected(_ sender: NSButton) {
		openLink(URL(string: "https://github.com/ptsochantaris/trailer")!)
	}

	override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing bufferingType: NSWindow.BackingStoreType, defer flag: Bool) {
		super.init(contentRect: contentRect, styleMask: style, backing: bufferingType, defer: flag)
		delegate = self
	}

	func windowWillClose(_ notification: Notification) {
		app.closedAboutWindow()
	}
}
