
final class AboutWindow: NSWindow, NSWindowDelegate {

	@IBOutlet weak var version: NSTextField!

	@IBAction func gitHubLinkSelected(sender: NSButton) {
		NSWorkspace.sharedWorkspace().openURL(NSURL(string: "https://github.com/ptsochantaris/trailer")!)
	}

	override init(contentRect: NSRect, styleMask aStyle: Int, backing bufferingType: NSBackingStoreType, `defer` flag: Bool) {
		super.init(contentRect: contentRect, styleMask: aStyle, backing: bufferingType, `defer`: flag)
		delegate = self
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func windowWillClose(notification: NSNotification) {
		app.closedAboutWindow()
	}
}
