
final class AdvancedReposWindow : NSWindow, NSWindowDelegate {

	@IBOutlet weak var refreshReposLabel: NSTextField!
	@IBOutlet weak var refreshButton: NSButton!
	@IBOutlet weak var activityDisplay: NSProgressIndicator!
	@IBOutlet weak var repoCheckStepper: NSStepper!

	@IBOutlet weak var autoAddRepos: NSButton!
	@IBOutlet weak var autoRemoveRepos: NSButton!
	@IBOutlet weak var hideArchivedRepos: NSButton!

	weak var prefs: PreferencesWindow?

	override func awakeFromNib() {
		super.awakeFromNib()
		delegate = self

		refreshButton.toolTip = "Reload all watchlists now. Normally Trailer does this by itself every few hours. You can control how often from the 'Display' tab."
		refreshReposLabel.toolTip = Settings.newRepoCheckPeriodHelp
		repoCheckStepper.toolTip = Settings.newRepoCheckPeriodHelp
		repoCheckStepper.floatValue = Settings.newRepoCheckPeriod
		autoAddRepos.integerValue = Settings.automaticallyAddNewReposFromWatchlist ? 1 : 0
		autoRemoveRepos.integerValue = Settings.automaticallyRemoveDeletedReposFromWatchlist ? 1 : 0
		hideArchivedRepos.integerValue = Settings.hideArchivedRepos ? 1 : 0

		newRepoCheckChanged(nil)

		updateActivity()

		let allServers = ApiServer.allApiServers(in: DataManager.main)
		if allServers.count > 1 {
			let m = NSMenuItem()
			m.title = "Select a server…"
			serverPicker.menu?.addItem(m)
		}
		for s in allServers {
			let m = NSMenuItem()
			m.representedObject = s
			m.title = s.label ?? "(no label)"
			serverPicker.menu?.addItem(m)
		}
	}

	func windowWillClose(_ notification: Notification) {
		prefs?.closedAdvancedWindow()
	}

	// chain this to updateActivity from the main repferences window
	func updateActivity() {
		if appIsRefreshing {
			refreshButton.isEnabled = false
			activityDisplay.startAnimation(nil)
		} else {
			refreshButton.isEnabled = ApiServer.someServersHaveAuthTokens(in: DataManager.main)
			activityDisplay.stopAnimation(nil)
			updateRemovableRepos()
		}
		addButton.isEnabled = !appIsRefreshing
		removeButton.isEnabled = !appIsRefreshing
	}

	private func updateRemovableRepos() {
		removeRepoList.removeAllItems()
		let manuallyAddedRepos = Repo.allItems(of: Repo.self, in: DataManager.main).filter { $0.manuallyAdded }
		if manuallyAddedRepos.count == 0 {
			let m = NSMenuItem()
			m.title = "You have not added any custom repositories"
			removeRepoList.menu?.addItem(m)
			removeRepoList.isEnabled = false
		} else if manuallyAddedRepos.count > 1 {
			let m = NSMenuItem()
			m.title = "Select a custom repository to remove…"
			removeRepoList.menu?.addItem(m)
			removeRepoList.isEnabled = true
		}
		for r in manuallyAddedRepos {
			let m = NSMenuItem()
			m.representedObject = r
			m.title = r.fullName ?? "(no label)"
			removeRepoList.menu?.addItem(m)
			removeRepoList.isEnabled = true
		}
	}

	@IBAction func newRepoCheckChanged(_ sender: NSStepper?) {
		Settings.newRepoCheckPeriod = repoCheckStepper.floatValue
		refreshReposLabel.stringValue = "Re-scan every \(repoCheckStepper.integerValue) hours"
	}

	@IBAction func refreshReposSelected(_ sender: NSButton?) {
		prefs?.refreshRepos()
	}

	@IBAction func autoHideArchivedReposSelected(_ sender: NSButton) {
		Settings.hideArchivedRepos = sender.integerValue == 1
		if Settings.hideArchivedRepos && Repo.hideArchivedRepos(in: DataManager.main) {
			prefs?.projectsTable.reloadData()
			updateRemovableRepos()
			app.updateAllMenus()
			DataManager.saveDB()
		}
	}

	@IBAction func automaticallyAddNewReposSelected(_ sender: NSButton) {
		let set = sender.integerValue == 1
		Settings.automaticallyAddNewReposFromWatchlist = set
		if set {
			prepareReposForSync()
		}
	}

	private func prepareReposForSync() {
		lastRepoCheck = .distantPast
		for a in ApiServer.allApiServers(in: DataManager.main) {
			for r in a.repos {
				r.resetSyncState()
			}
		}
		DataManager.saveDB()
	}

	@IBAction func automaticallyRemoveReposSelected(_ sender: NSButton) {
		let set = sender.integerValue == 1
		Settings.automaticallyRemoveDeletedReposFromWatchlist = set
		if set {
			prepareReposForSync()
		}
		DataManager.saveDB()
	}

	@IBOutlet weak var serverPicker: NSPopUpButton!
	@IBOutlet weak var newRepoOwner: NSTextField!
	@IBOutlet weak var newRepoName: NSTextField!
	@IBOutlet weak var newRepoSpinner: NSProgressIndicator!
	@IBOutlet weak var addButton: NSButton!
	@IBAction func addSelected(_ sender: NSButton) {
		let name = newRepoName.stringValue.trim
		let owner = newRepoOwner.stringValue.trim
		guard
			!name.isEmpty,
			!owner.isEmpty,
			let server = serverPicker.selectedItem?.representedObject as? ApiServer
			else {
				let alert = NSAlert()
				alert.messageText = "Missing Information"
				alert.informativeText = "Please select a server, provide an owner/org name, and the name of the repo. Usually this info is part of the repository's URL, like https://github.com/owner_or_org/repo_name"
				alert.addButton(withTitle: "OK")
				alert.beginSheetModal(for: self, completionHandler: nil)
				return
		}

		newRepoSpinner.startAnimation(nil)
		addButton.isEnabled = false

		API.fetchRepo(named: name, owner: owner, from: server) { error in

			self.newRepoSpinner.stopAnimation(nil)
			self.addButton.isEnabled = true
			preferencesDirty = true

			let alert = NSAlert()
			if let e = error {
				alert.messageText = "Fetching Repository Information Failed"
				alert.informativeText = e.localizedDescription
			} else {
				alert.messageText = "Repository added"
				if Settings.displayPolicyForNewPrs == Int(RepoDisplayPolicy.hide.rawValue) && Settings.displayPolicyForNewIssues == Int(RepoDisplayPolicy.hide.rawValue) {
					alert.informativeText = "WARNING: While the repository has been added successfully to your list, your default settings specify that it should be hidden. You probably want to change its visibility in the main repositories list."
				} else {
					alert.informativeText = "The new repository has been added to your local list. Trailer will refresh after you close preferences to fetch any items from it."
				}
				DataManager.saveDB()
				self.prefs?.projectsTable.reloadData()
				self.updateRemovableRepos()
				app.updateAllMenus()
			}
			alert.addButton(withTitle: "OK")
			alert.beginSheetModal(for: self, completionHandler: nil)
		}
	}

	@IBOutlet weak var removeRepoList: NSPopUpButtonCell!
	@IBOutlet weak var removeButton: NSButton!
	@IBAction func removeSelected(_ sender: NSButton) {
		guard let repo = removeRepoList.selectedItem?.representedObject as? Repo else { return }
		DataManager.main.delete(repo)
		DataManager.saveDB()
		prefs?.projectsTable.reloadData()
		updateRemovableRepos()
		app.updateAllMenus()
	}
}
