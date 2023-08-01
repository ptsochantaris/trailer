import Cocoa

final class SetupAssistant: NSWindow, NSWindowDelegate, NSControlTextEditingDelegate {
    @IBOutlet private var quickstart: NSTextField!
    @IBOutlet private var buttonLink: NSButton!
    @IBOutlet private var buttonDescription: NSTextField!
    @IBOutlet private var tokenHolder: NSTextField!
    @IBOutlet private var startAtLogin: NSButton!
    @IBOutlet private var completeSetup: NSButton!
    @IBOutlet private var spinner: NSProgressIndicator!
    @IBOutlet private var welcomeLabel: NSTextField!
    @IBOutlet private var importButton: NSButton!

    private let newServer = ApiServer.allApiServers(in: DataManager.main).first!

    @MainActor
    override func awakeFromNib() {
        Settings.isAppLoginItem = true
        startAtLogin.integerValue = 1
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing bufferingType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: bufferingType, defer: flag)
        delegate = self
    }

    func windowWillClose(_: Notification) {
        app.closedSetupAssistant()
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        spinner.isHidden
    }

    @IBAction private func createTokenSelected(_: NSButton) {
        let address = "https://github.com/settings/tokens/new"
        openLink(URL(string: address)!)
    }

    func controlTextDidChange(_ obj: Notification) {
        if let t = obj.object as? NSTextField {
            completeSetup.isEnabled = !t.stringValue.isEmpty
        }
    }

    @IBAction private func startAtLoginSelected(_ sender: NSButton) {
        Settings.isAppLoginItem = sender.integerValue == 1
    }

    @IBAction private func testAndCompleteSelected(_: NSButton) {
        let token = tokenHolder.stringValue.trim
        if token.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Please enter your personal access token first"
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: self) { _ in
                self.normalState()
            }
        } else {
            testingState()
            Task {
                do {
                    try await newServer.test()
                    quickstart.stringValue = "\nFetching your watchlist. This will take a moment…"
                    Settings.lastSuccessfulRefresh = nil
                    await app.startRefreshIfItIsDue()
                    await checkRefreshDone()
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "Testing the token failed - please check that you have pasted your token correctly"
                    alert.informativeText = error.localizedDescription
                    _ = alert.addButton(withTitle: "OK")
                    alert.beginSheetModal(for: self) { [weak self] _ in
                        self?.normalState()
                    }
                }
            }
        }
    }

    private func checkRefreshDone() async {
        while API.isRefreshing {
            try? await Task.sleep(nanoseconds: 200 * NSEC_PER_MSEC)
        }

        if newServer.lastSyncSucceeded {
            close()

            guard let prefs = app.showPreferencesWindow(andSelect: 1) else {
                return
            }

            let alert = NSAlert()
            alert.messageText = "Setup complete!"
            alert.informativeText = "This tab contains your watchlist, with view settings for each repository. Be sure to enable only the repos you need, in order to keep API usage low. Trailer will load data from the active repositories once you close the preferences window.\n\nYou can tweak options & behaviour from the other tabs.\n\nTrailer has read-only access to your GitHub data, so feel free to experiment, you can't damage your data or settings on GitHub."
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: prefs) { _ in
                // Nothing
            }

        } else {
            let alert = NSAlert()
            alert.messageText = "Syncing with this server failed - please check that your network connection is working and that you have pasted your token correctly"
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: self) { _ in
                self.normalState()
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
        spinner.isHidden = true
        importButton.isHidden = false
    }

    private func testingState() {
        spinner.startAnimation(nil)
        quickstart.stringValue = "\nTesting your access token…"
        spinner.isHidden = false
        buttonLink.isHidden = true
        buttonDescription.isHidden = true
        tokenHolder.isHidden = true
        startAtLogin.isHidden = true
        completeSetup.isHidden = true
        welcomeLabel.isHidden = true
        importButton.isHidden = true
        newServer.authToken = tokenHolder.stringValue.trim
        newServer.lastSyncSucceeded = true
    }

    @IBAction private func importSettingsSelected(_: NSButton) {
        let o = NSOpenPanel()
        o.title = "Import Settings From File…"
        o.prompt = "Import"
        o.nameFieldLabel = "Settings File"
        o.message = "Import Settings From File…"
        o.isExtensionHidden = false
        o.allowedFileTypes = ["trailerSettings"]
        o.beginSheetModal(for: self) { [weak self] response in
            guard let self else { return }
            if response == .OK, let url = o.url {
                Task { @MainActor in
                    if await app.tryLoadSettings(from: url, skipConfirm: Settings.dontConfirmSettingsImport) {
                        self.close()
                    }
                }
            }
        }
    }
}
