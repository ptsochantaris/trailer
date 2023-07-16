import Cocoa

final class AdvancedReposWindow: NSWindow, NSWindowDelegate {
    @IBOutlet private var refreshReposLabel: NSTextField!
    @IBOutlet private var refreshButton: NSButton!
    @IBOutlet private var activityDisplay: NSProgressIndicator!
    @IBOutlet private var repoCheckStepper: NSStepper!

    @IBOutlet private var autoAddRepos: NSButton!
    @IBOutlet private var autoRemoveRepos: NSButton!
    @IBOutlet private var hideArchivedRepos: NSButton!

    @IBOutlet private var syncAuthoredPrs: NSButton!
    @IBOutlet private var syncAuthoredIssues: NSButton!

    weak var prefs: PreferencesWindow?

    @MainActor
    override func awakeFromNib() {
        super.awakeFromNib()
        delegate = self

        refreshButton.toolTip = "Reload all watchlists now. Normally Trailer does this by itself every few hours. You can control how often from the 'Display' tab."
        refreshReposLabel.toolTip = Settings.newRepoCheckPeriodHelp
        repoCheckStepper.toolTip = Settings.newRepoCheckPeriodHelp
        repoCheckStepper.floatValue = Settings.newRepoCheckPeriod
        syncAuthoredPrs.toolTip = Settings.queryAuthoredPRsHelp
        syncAuthoredIssues.toolTip = Settings.queryAuthoredIssuesHelp

        autoAddRepos.integerValue = Settings.automaticallyAddNewReposFromWatchlist ? 1 : 0
        autoRemoveRepos.integerValue = Settings.automaticallyRemoveDeletedReposFromWatchlist ? 1 : 0
        hideArchivedRepos.integerValue = Settings.hideArchivedRepos ? 1 : 0
        syncAuthoredPrs.integerValue = Settings.queryAuthoredPRs ? 1 : 0
        syncAuthoredIssues.integerValue = Settings.queryAuthoredIssues ? 1 : 0

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

    func windowWillClose(_: Notification) {
        prefs?.closedAdvancedWindow()
    }

    // chain this to updateActivity from the main repferences window
    func updateActivity() {
        let refreshing = API.isRefreshing
        if refreshing {
            refreshButton.isEnabled = false
            activityDisplay.startAnimation(nil)
        } else {
            refreshButton.isEnabled = ApiServer.someServersHaveAuthTokens(in: DataManager.main)
            activityDisplay.stopAnimation(nil)
            updateRemovableRepos()
        }
        addButton.isEnabled = !refreshing
        removeButton.isEnabled = !refreshing
    }

    private func updateRemovableRepos() {
        removeRepoList.removeAllItems()
        let manuallyAddedRepos = Repo.allItems(in: DataManager.main).filter(\.manuallyAdded)
        if manuallyAddedRepos.isEmpty {
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

    @IBAction private func newRepoCheckChanged(_: NSStepper?) {
        Settings.newRepoCheckPeriod = repoCheckStepper.floatValue
        refreshReposLabel.stringValue = "Re-scan every \(repoCheckStepper.integerValue) hours"
    }

    @IBAction private func refreshReposSelected(_: NSButton?) {
        prefs?.refreshRepos()
    }

    @IBAction private func autoHideArchivedReposSelected(_ sender: NSButton) {
        Settings.hideArchivedRepos = sender.integerValue == 1
        if Settings.hideArchivedRepos, Repo.hideArchivedRepos(in: DataManager.main) {
            prefs?.reloadRepositories()
            updateRemovableRepos()
            Task {
                await app.updateAllMenus()
                await DataManager.saveDB()
            }
        }
    }

    @IBAction private func queryAuthoredPRsSelected(_ sender: NSButton) {
        Settings.queryAuthoredPRs = (sender.integerValue == 1)
        lastRepoCheck = .distantPast
        preferencesDirty = true
    }

    @IBAction private func queryAuthoredIssuesSelected(_ sender: NSButton) {
        Settings.queryAuthoredIssues = (sender.integerValue == 1)
        lastRepoCheck = .distantPast
        preferencesDirty = true
    }

    @IBAction private func automaticallyAddNewReposSelected(_ sender: NSButton) {
        let set = sender.integerValue == 1
        Settings.automaticallyAddNewReposFromWatchlist = set
        Task {
            if set {
                await prepareReposForSync()
            }
        }
    }

    private func prepareReposForSync() async {
        lastRepoCheck = .distantPast
        for a in ApiServer.allApiServers(in: DataManager.main) {
            for r in a.repos {
                r.resetSyncState()
            }
        }
        await DataManager.saveDB()
    }

    @IBAction private func automaticallyRemoveReposSelected(_ sender: NSButton) {
        let set = sender.integerValue == 1
        Settings.automaticallyRemoveDeletedReposFromWatchlist = set
        Task {
            if set {
                await prepareReposForSync()
            }
            await DataManager.saveDB()
        }
    }

    @IBOutlet private var serverPicker: NSPopUpButton!
    @IBOutlet private var newRepoOwner: NSTextField!
    @IBOutlet private var newRepoName: NSTextField!
    @IBOutlet private var newRepoSpinner: NSProgressIndicator!
    @IBOutlet private var addButton: NSButton!

    @IBAction private func addSelected(_: NSButton) {
        let name = newRepoName.stringValue.trim
        let owner = newRepoOwner.stringValue.trim
        guard
            !name.isEmpty,
            !owner.isEmpty,
            let server = serverPicker.selectedItem?.representedObject as? ApiServer
        else {
            let alert = NSAlert()
            alert.messageText = "Missing Information"
            alert.informativeText = "Please select a server, provide an owner/org name, and the name of the repo (or a star for all repos). Usually this info is part of the repository's URL, like https://github.com/owner_or_org/repo_name"
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: self)
            return
        }

        newRepoSpinner.startAnimation(nil)
        addButton.isEnabled = false
        defer {
            self.newRepoSpinner.stopAnimation(nil)
            self.addButton.isEnabled = true
        }

        Task {
            if name == "*" {
                let alert = NSAlert()
                do {
                    try await API.fetchAllRepos(owner: owner, from: server, moc: DataManager.main)
                    preferencesDirty = true
                    let addedCount = Repo.newItems(in: DataManager.main).count
                    alert.messageText = "\(addedCount) repositories added for '\(owner)'"
                    if Settings.displayPolicyForNewPrs == Int(RepoDisplayPolicy.hide.rawValue), Settings.displayPolicyForNewIssues == Int(RepoDisplayPolicy.hide.rawValue) {
                        alert.informativeText = "WARNING: While \(addedCount) repositories have been added successfully to your list, your default settings specify that they should be hidden. You probably want to change their visibility from the repositories list."
                    } else {
                        alert.informativeText = "The new repositories have been added to your local list. Trailer will refresh after you close preferences to fetch any items from them."
                    }
                    await DataManager.saveDB()
                    prefs?.reloadRepositories()
                    updateRemovableRepos()
                    await app.updateAllMenus()
                } catch {
                    alert.messageText = "Fetching Repository Information Failed"
                    alert.informativeText = error.localizedDescription
                }
                _ = alert.addButton(withTitle: "OK")
                _ = await alert.beginSheetModal(for: self)
            } else {
                let alert = NSAlert()
                do {
                    try await API.fetchRepo(named: name, owner: owner, from: server, moc: DataManager.main)
                    preferencesDirty = true
                    alert.messageText = "Repository added"
                    if Settings.displayPolicyForNewPrs == Int(RepoDisplayPolicy.hide.rawValue), Settings.displayPolicyForNewIssues == Int(RepoDisplayPolicy.hide.rawValue) {
                        alert.informativeText = "WARNING: While the repository has been added successfully to your list, your default settings specify that it should be hidden. You probably want to change its visibility from the repositories list."
                    } else {
                        alert.informativeText = "The new repository has been added to your local list. Trailer will refresh after you close preferences to fetch any items from it."
                    }
                    await DataManager.saveDB()
                    prefs?.reloadRepositories()
                    updateRemovableRepos()
                    await app.updateAllMenus()
                } catch {
                    alert.messageText = "Fetching Repository Information Failed"
                    alert.informativeText = error.localizedDescription
                }
                _ = alert.addButton(withTitle: "OK")
                _ = await alert.beginSheetModal(for: self)
            }
        }
    }

    @IBOutlet private var removeRepoList: NSPopUpButtonCell!
    @IBOutlet private var removeButton: NSButton!
    @IBAction private func removeSelected(_: NSButton) {
        guard let repo = removeRepoList.selectedItem?.representedObject as? Repo else { return }
        DataManager.main.delete(repo)
        Task {
            await DataManager.saveDB()
            prefs?.reloadRepositories()
            updateRemovableRepos()
            await app.updateAllMenus()
        }
    }
}
