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

    @IBOutlet private var allNewPrsSetting: NSPopUpButton!
    @IBOutlet private var allNewIssuesSetting: NSPopUpButton!

    weak var prefs: PreferencesWindow?

    @MainActor
    override func awakeFromNib() {
        super.awakeFromNib()
        delegate = self

        allNewPrsSetting.addItems(withTitles: RepoDisplayPolicy.labels)
        allNewPrsSetting.toolTip = "The visibility settings you would like to apply by default for Pull Requests if a new repository is added in your watchlist."
        allNewPrsSetting.selectItem(at: Settings.displayPolicyForNewPrs.rawValue)

        allNewIssuesSetting.addItems(withTitles: RepoDisplayPolicy.labels)
        allNewIssuesSetting.toolTip = "The visibility settings you would like to apply by default for Pull Requests if a new repository is added in your watchlist."
        allNewIssuesSetting.selectItem(at: Settings.displayPolicyForNewIssues.rawValue)

        refreshButton.toolTip = "Reload all watchlists now. Normally Trailer does this by itself every few hours. You can control how often from the 'Display' tab."
        refreshReposLabel.toolTip = Settings.newRepoCheckPeriodHelp
        repoCheckStepper.toolTip = Settings.newRepoCheckPeriodHelp
        repoCheckStepper.floatValue = Settings.newRepoCheckPeriod
        syncAuthoredPrs.toolTip = Settings.queryAuthoredPRsHelp
        syncAuthoredIssues.toolTip = Settings.queryAuthoredIssuesHelp

        autoAddRepos.integerValue = Settings.automaticallyAddNewReposFromWatchlist.asInt
        autoRemoveRepos.integerValue = Settings.automaticallyRemoveDeletedReposFromWatchlist.asInt
        hideArchivedRepos.integerValue = Settings.hideArchivedRepos.asInt
        syncAuthoredPrs.integerValue = Settings.queryAuthoredPRs.asInt
        syncAuthoredIssues.integerValue = Settings.queryAuthoredIssues.asInt

        newRepoCheckChanged(nil)

        updateActivity()
    }

    @IBAction private func allNewPrsPolicySelected(_ sender: NSPopUpButton) {
        Settings.displayPolicyForNewPrs = RepoDisplayPolicy(rawValue: sender.indexOfSelectedItem) ?? Settings.displayPolicyForNewPrs
    }

    @IBAction private func allNewIssuesPolicySelected(_ sender: NSPopUpButton) {
        Settings.displayPolicyForNewIssues = RepoDisplayPolicy(rawValue: sender.indexOfSelectedItem) ?? Settings.displayPolicyForNewIssues
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
}
