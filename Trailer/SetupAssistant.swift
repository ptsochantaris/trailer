
class SetupAssistant: NSWindow, NSWindowDelegate {

	@IBOutlet weak var quickstart: NSTextField!
	@IBOutlet weak var buttonLink: NSButton!
	@IBOutlet weak var buttonDescription: NSTextField!
	@IBOutlet weak var tokenHolder: NSTextField!
	@IBOutlet weak var startAtLogin: NSButton!
	@IBOutlet weak var completeSetup: NSButton!
	@IBOutlet weak var spinner: NSProgressIndicator!
	@IBOutlet weak var welcomeLabel: NSTextField!

	private var state = 0
	private let newServer = ApiServer.allApiServersInMoc(mainObjectContext).first!

	override func awakeFromNib() {
		StartupLaunch.setLaunchOnLogin(true)
		startAtLogin.integerValue = 1
	}

	override init(contentRect: NSRect, styleMask aStyle: Int, backing bufferingType: NSBackingStoreType, defer flag: Bool) {
		super.init(contentRect: contentRect, styleMask: aStyle, backing: bufferingType, defer: flag)
		delegate = self
	}

	required init?(coder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}

	@IBAction func startAtLoginSelected(sender: NSButton) {
		StartupLaunch.setLaunchOnLogin(sender.integerValue==1)
	}

	func windowWillClose(notification: NSNotification) {
		app.closedSetupAssistant()
	}

	func windowShouldClose(sender: AnyObject) -> Bool {
		return spinner.hidden
	}

	@IBAction func createTokenSelected(sender: NSButton) {
		let address = "https://github.com/settings/tokens/new"
		NSWorkspace.sharedWorkspace().openURL(NSURL(string: address)!)
	}

	override func controlTextDidChange(obj: NSNotification) {
		if let t = obj.object as? NSTextField {
			completeSetup.enabled = !t.stringValue.isEmpty
		}
	}

	@IBAction func testAndCompleteSelected(sender: NSButton) {
		let token = (tokenHolder.stringValue as NSString).stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
		if token.isEmpty {
			let alert = NSAlert()
			alert.messageText = "Please enter your personal access token first"
			alert.addButtonWithTitle("OK")
			alert.beginSheetModalForWindow(self, completionHandler: { response in
				self.normalState()
			})
		} else {
			testingState()
			api.testApiToServer(newServer, callback: { error in
				if let e = error {
					let alert = NSAlert()
					alert.messageText = "Testing this server failed - please check that you have pasted your token correctly"
					alert.informativeText = e.localizedDescription
					alert.addButtonWithTitle("OK")
					alert.beginSheetModalForWindow(self, completionHandler: { response in
						self.normalState()
					})
				} else {
					Settings.lastSuccessfulRefresh = nil
					app.refreshReposSelected(nil)
					NSTimer.scheduledTimerWithTimeInterval(1.0, target: self, selector: Selector("checkRefreshDone:"), userInfo: nil, repeats: true)
				}
			})
		}
	}

	func checkRefreshDone(t: NSTimer) {
		if !app.isRefreshing {

			state++

			if state==1 {
				quickstart.stringValue = "\nSyncing your GitHub PR info for the first time.\n\nThis could take a little while, please wait..."
				Settings.lastSuccessfulRefresh = nil
				app.startRefreshIfItIsDue()
			} else if state==2 {
				if newServer.lastSyncSucceeded?.boolValue ?? false {
					self.close()
					let alert = NSAlert()
					alert.messageText = "Setup complete!"
					alert.informativeText = "You can tweak settings & behaviour from the preferences window.\n\nTrailer will only read from your Github data, so feel free to experiment with settings and options, you can't hurt your data or settings on GitHub."
					alert.addButtonWithTitle("OK")
					alert.runModal()
				} else {
					let alert = NSAlert()
					alert.messageText = "Syncing withg this server failed - please check that your network connection is working and that you have pasted your token correctly"
					alert.addButtonWithTitle("OK")
					alert.beginSheetModalForWindow(self, completionHandler: { response in
						self.normalState()
					})
				}
			}
		}
	}

	private func normalState() {
		spinner.stopAnimation(nil)
		quickstart.stringValue = "Quickstart"
		buttonLink.hidden = false
		buttonDescription.hidden = false
		tokenHolder.hidden = false
		startAtLogin.hidden = false
		completeSetup.hidden = false
		welcomeLabel.hidden = false
		spinner.hidden = true
	}

	private func testingState() {
		spinner.startAnimation(nil)
		quickstart.stringValue = "\nTesting your access token..."
		spinner.hidden = false
		buttonLink.hidden = true
		buttonDescription.hidden = true
		tokenHolder.hidden = true
		startAtLogin.hidden = true
		completeSetup.hidden = true
		welcomeLabel.hidden = true
		api.resetBadLinks()
		let token = (tokenHolder.stringValue as NSString).stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
		newServer.authToken = token
		newServer.lastSyncSucceeded = true
	}
}
