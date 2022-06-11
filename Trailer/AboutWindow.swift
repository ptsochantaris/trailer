import Cocoa

final class AboutWindow: NSWindow, NSWindowDelegate {
    @IBOutlet var version: NSTextField!

    @IBAction private func gitHubLinkSelected(_: NSButton) {
        openLink(URL(string: "https://github.com/ptsochantaris/trailer")!)
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing bufferingType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: bufferingType, defer: flag)
        delegate = self
    }

    @IBAction func checkForUpdates(sender _: NSButton) {
        app.performUpdateCheck()
    }

    func windowWillClose(_: Notification) {
        app.closedAboutWindow()
    }
}
