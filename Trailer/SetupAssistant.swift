
final class SetupAssistant: NSWindow, NSWindowDelegate {

	@IBOutlet weak var quickstart: NSTextField!
	@IBOutlet weak var buttonLink: NSButton!
	@IBOutlet weak var buttonDescription: NSTextField!
	@IBOutlet weak var tokenHolder: NSTextField!
	@IBOutlet weak var startAtLogin: NSButton!
	@IBOutlet weak var completeSetup: NSButton!
	@IBOutlet weak var spinner: NSProgressIndicator!
	@IBOutlet weak var welcomeLabel: NSTextField!
	@IBOutlet weak var trackIssues: NSButton!

	private let newServer = ApiServer.allApiServers(in: mainObjectContext).first!
	private var checkTimer: Timer?

	override func awakeFromNib() {
		StartupLaunch.setLaunchOnLogin(true)
		startAtLogin.integerValue = 1
		trackIssues.integerValue = 1
		Settings.displayPolicyForNewIssues = Int(RepoDisplayPolicy.all.rawValue)
	}

	override init(contentRect: NSRect, styleMask style: NSWindowStyleMask, backing bufferingType: NSBackingStoreType, defer flag: Bool) {
		super.init(contentRect: contentRect, styleMask: style, backing: bufferingType, defer: flag)
		delegate = self
	}

	func windowWillClose(_ notification: Notification) {
		app.closedSetupAssistant()
	}

	func windowShouldClose(_ sender: AnyObject) -> Bool {
		return spinner.isHidden
	}

	@IBAction func createTokenSelected(_ sender: NSButton) {
		let address = "https://github.com/settings/tokens/new"
		NSWorkspace.shared().open(URL(string: address)!)
	}

	override func controlTextDidChange(_ obj: Notification) {
		if let t = obj.object as? NSTextField {
			completeSetup.isEnabled = !t.stringValue.isEmpty
		}
	}

	@IBAction func startAtLoginSelected(_ sender: NSButton) {
		StartupLaunch.setLaunchOnLogin(startAtLogin.integerValue==1)
	}

	@IBAction func trackIssuesSelected(_ sender: NSButton) {
		Settings.displayPolicyForNewIssues = Int(sender.integerValue==1 ? RepoDisplayPolicy.all.rawValue : RepoDisplayPolicy.hide.rawValue)
	}

	@IBAction func testAndCompleteSelected(_ sender: NSButton) {

		let token = tokenHolder.stringValue.trim()
		if token.isEmpty {
			let alert = NSAlert()
			alert.messageText = "Please enter your personal access token first"
			alert.addButton(withTitle: "OK")
			alert.beginSheetModal(for: self) { [weak self] response in
				self?.normalState()
			}
		} else {
			testingState()
			api.testApi(to: newServer) { [weak self] error in
				if let s = self {
					if let e = error {
						let alert = NSAlert()
						alert.messageText = "Testing the token failed - please check that you have pasted your token correctly"
						alert.informativeText = e.localizedDescription
						alert.addButton(withTitle: "OK")
						alert.beginSheetModal(for: s) { response in
							s.normalState()
						}
					} else {
						s.quickstart.stringValue = "\nSyncing GitHub data for the first time.\n\nThis could take a little while, please wait..."
						Settings.lastSuccessfulRefresh = nil
						app.startRefreshIfItIsDue()
						s.checkTimer = Timer.scheduledTimer(timeInterval: 1.0, target: s, selector: #selector(SetupAssistant.checkRefreshDone(_:)), userInfo: nil, repeats: true)
					}
				}
			}
		}
	}

	func checkRefreshDone(_ t: Timer) {
		if !appIsRefreshing {

			checkTimer?.invalidate()
			checkTimer = nil

			if newServer.lastSyncSucceeded {
				close()
				let alert = NSAlert()
				alert.messageText = "Setup complete!"
				alert.informativeText = "You can tweak settings & behaviour from the preferences window.\n\nTrailer only has read-only access to your GitHub data, so feel free to experiment, you can't damage your data or settings on GitHub."
				alert.addButton(withTitle: "OK")
				alert.runModal()
			} else {
				let alert = NSAlert()
				alert.messageText = "Syncing with this server failed - please check that your network connection is working and that you have pasted your token correctly"
				alert.addButton(withTitle: "OK")
				alert.beginSheetModal(for: self) { [weak self] response in
					self?.normalState()
				}
			}
		}
	}

	private func normalState() {
		spinner.stopAnimation(nil)
		quickstart.stringValue = "Quickstart"
		buttonLink.isHidden = false
		buttonDescription.isHidden = false
		tokenHolder.isHidden = false
		startAtLogin.isHidden = false
		completeSetup.isHidden = false
		welcomeLabel.isHidden = false
		trackIssues.isHidden = false
		spinner.isHidden = true
	}

	private func testingState() {
		spinner.startAnimation(nil)
		quickstart.stringValue = "\nTesting your access token..."
		spinner.isHidden = false
		buttonLink.isHidden = true
		buttonDescription.isHidden = true
		tokenHolder.isHidden = true
		startAtLogin.isHidden = true
		completeSetup.isHidden = true
		welcomeLabel.isHidden = true
		trackIssues.isHidden = true
		newServer.authToken = tokenHolder.stringValue.trim()
		newServer.lastSyncSucceeded = true
	}
}
