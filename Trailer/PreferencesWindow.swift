
import Foundation

final class PreferencesWindow : NSWindow, NSWindowDelegate, NSTableViewDelegate, NSTableViewDataSource, NSTabViewDelegate {

	private var deferredUpdateTimer: PopTimer!
	private var serversDirty = false

	func reset() {
		preferencesDirty = true
		api.resetAllStatusChecks()
		api.resetAllLabelChecks()
		Settings.lastSuccessfulRefresh = nil
		lastRepoCheck = Date.distantPast
		projectsTable.reloadData()
		deferredUpdateTimer.push()
	}

	// Preferences window
	@IBOutlet weak var refreshButton: NSButton!
	@IBOutlet weak var activityDisplay: NSProgressIndicator!
	@IBOutlet weak var projectsTable: NSTableView!
	@IBOutlet weak var versionNumber: NSTextField!
	@IBOutlet weak var launchAtStartup: NSButton!
	@IBOutlet weak var refreshDurationLabel: NSTextField!
	@IBOutlet weak var refreshDurationStepper: NSStepper!
	@IBOutlet weak var hideUncommentedPrs: NSButton!
	@IBOutlet weak var repoFilter: NSTextField!
	@IBOutlet weak var showAllComments: NSButton!
	@IBOutlet weak var sortingOrder: NSButton!
	@IBOutlet weak var sortModeSelect: NSPopUpButton!
	@IBOutlet weak var includeRepositoriesInFiltering: NSButton!
	@IBOutlet weak var groupByRepo: NSButton!
	@IBOutlet weak var markUnmergeableOnUserSectionsOnly: NSButton!
	@IBOutlet weak var repoCheckLabel: NSTextField!
	@IBOutlet weak var repoCheckStepper: NSStepper!
	@IBOutlet weak var countOnlyListedItems: NSButton!
	@IBOutlet weak var checkForUpdatesAutomatically: NSButton!
	@IBOutlet weak var checkForUpdatesLabel: NSTextField!
	@IBOutlet weak var checkForUpdatesSelector: NSStepper!
	@IBOutlet weak var openPrAtFirstUnreadComment: NSButton!
	@IBOutlet weak var logActivityToConsole: NSButton!
	@IBOutlet weak var commentAuthorBlacklist: NSTokenField!

	// History
	@IBOutlet weak var prMergedPolicy: NSPopUpButton!
	@IBOutlet weak var prClosedPolicy: NSPopUpButton!
	@IBOutlet weak var dontKeepPrsMergedByMe: NSButton!
	@IBOutlet weak var dontConfirmRemoveAllMerged: NSButton!
	@IBOutlet weak var dontConfirmRemoveAllClosed: NSButton!
	@IBOutlet weak var removeNotificationsWhenItemIsRemoved: NSButton!

	// Statuses
	@IBOutlet weak var showStatusItems: NSButton!
	@IBOutlet weak var makeStatusItemsSelectable: NSButton!
	@IBOutlet weak var statusItemRescanLabel: NSTextField!
	@IBOutlet weak var statusItemRefreshCounter: NSStepper!
	@IBOutlet weak var statusItemsRefreshNote: NSTextField!
	@IBOutlet weak var notifyOnStatusUpdates: NSButton!
	@IBOutlet weak var notifyOnStatusUpdatesForAllPrs: NSButton!
	@IBOutlet weak var statusTermMenu: NSPopUpButton!
	@IBOutlet weak var statusTermsField: NSTokenField!
	@IBOutlet weak var hidePrsThatDontPass: NSButton!
	@IBOutlet weak var hidePrsThatDontPassOnlyInAll: NSButton!

	// Comments
	@IBOutlet weak var disableAllCommentNotifications: NSButton!
	@IBOutlet weak var assumeCommentsBeforeMineAreRead: NSButton!
	@IBOutlet weak var newMentionMovePolicy: NSPopUpButton!
	@IBOutlet weak var teamMentionMovePolicy: NSPopUpButton!
	@IBOutlet weak var newItemInOwnedRepoMovePolicy: NSPopUpButton!

	// Display
	@IBOutlet weak var useVibrancy: NSButton!
	@IBOutlet weak var includeLabelsInFiltering: NSButton!
	@IBOutlet weak var includeTitlesInFiltering: NSButton!
	@IBOutlet weak var includeMilestonesInFiltering: NSButton!
	@IBOutlet weak var includeAssigneeNamesInFiltering: NSButton!
	@IBOutlet weak var includeStatusesInFiltering: NSButton!
	@IBOutlet weak var grayOutWhenRefreshing: NSButton!
	@IBOutlet weak var assignedPrHandlingPolicy: NSPopUpButton!
    @IBOutlet weak var includeServersInFiltering: NSButton!
    @IBOutlet weak var includeUsersInFiltering: NSButton!
	@IBOutlet weak var includeNumbersInFiltering: NSButton!
	@IBOutlet weak var refreshReposLabel: NSTextField!
	@IBOutlet weak var refreshItemsLabel: NSTextField!
	@IBOutlet weak var showCreationDates: NSButton!
	@IBOutlet weak var hideAvatars: NSButton!
	@IBOutlet weak var showSeparateApiServersInMenu: NSButton!
	@IBOutlet weak var displayRepositoryNames: NSButton!

	// Labels
	@IBOutlet weak var labelRescanLabel: NSTextField!
	@IBOutlet weak var labelRefreshNote: NSTextField!
	@IBOutlet weak var labelRefreshCounter: NSStepper!
	@IBOutlet weak var showLabels: NSButton!

	// Servers
	@IBOutlet weak var serverList: NSTableView!
	@IBOutlet weak var apiServerName: NSTextField!
	@IBOutlet weak var apiServerApiPath: NSTextField!
	@IBOutlet weak var apiServerWebPath: NSTextField!
	@IBOutlet weak var apiServerAuthToken: NSTextField!
	@IBOutlet weak var apiServerSelectedBox: NSBox!
	@IBOutlet weak var apiServerTestButton: NSButton!
	@IBOutlet weak var apiServerDeleteButton: NSButton!
	@IBOutlet weak var apiServerReportError: NSButton!

	// Snoozing
	@IBOutlet weak var snoozePresetsList: NSTableView!
	@IBOutlet weak var snoozeTypeDuration: NSButton!
	@IBOutlet weak var snoozeTypeDateTime: NSButton!
	@IBOutlet weak var snoozeDurationDays: NSPopUpButton!
	@IBOutlet weak var snoozeDurationHours: NSPopUpButton!
	@IBOutlet weak var snoozeDurationMinutes: NSPopUpButton!
	@IBOutlet weak var snoozeDateTimeDay: NSPopUpButton!
	@IBOutlet weak var snoozeDateTimeHour: NSPopUpButton!
	@IBOutlet weak var snoozeDateTimeMinute: NSPopUpButton!
	@IBOutlet weak var snoozeDeletePreset: NSButton!
	@IBOutlet weak var snoozeUp: NSButton!
	@IBOutlet weak var snoozeDown: NSButton!
	@IBOutlet weak var snoozeWakeOnComment: NSButton!
	@IBOutlet weak var snoozeWakeOnMention: NSButton!
	@IBOutlet weak var snoozeWakeOnStatusUpdate: NSButton!
	@IBOutlet weak var hideSnoozedItems: NSButton!
	@IBOutlet weak var snoozeWakeLabel: NSTextField!

	@IBOutlet weak var autoSnoozeSelector: NSStepper!
	@IBOutlet weak var autoSnoozeLabel: NSTextField!

	// Misc
	@IBOutlet weak var repeatLastExportAutomatically: NSButton!
	@IBOutlet weak var lastExportReport: NSTextField!
	@IBOutlet weak var dumpApiResponsesToConsole: NSButton!

	// Keyboard
	@IBOutlet weak var hotkeyEnable: NSButton!
	@IBOutlet weak var hotkeyCommandModifier: NSButton!
	@IBOutlet weak var hotkeyOptionModifier: NSButton!
	@IBOutlet weak var hotkeyShiftModifier: NSButton!
	@IBOutlet weak var hotkeyLetter: NSPopUpButton!
	@IBOutlet weak var hotKeyHelp: NSTextField!
	@IBOutlet weak var hotKeyContainer: NSBox!
	@IBOutlet weak var hotkeyControlModifier: NSButton!

	// Watchlist
	@IBOutlet weak var allPrsSetting: NSPopUpButton!
	@IBOutlet weak var allIssuesSetting: NSPopUpButton!
	@IBOutlet weak var allHidingSetting: NSPopUpButton!
	@IBOutlet weak var allNewPrsSetting: NSPopUpButton!
	@IBOutlet weak var allNewIssuesSetting: NSPopUpButton!

	// Tabs
	@IBOutlet weak var tabs: NSTabView!

	override func awakeFromNib() {
		super.awakeFromNib()
		delegate = self

		updateAllItemSettingButtons()
		fillSnoozingDropdowns()

		allNewPrsSetting.addItems(withTitles: RepoDisplayPolicy.labels)
		allNewIssuesSetting.addItems(withTitles: RepoDisplayPolicy.labels)

		addTooltips()
		reloadSettings()

		versionNumber.stringValue = versionString()

		let selectedIndex = min(tabs.numberOfTabViewItems-1, Settings.lastPreferencesTabSelectedOSX)
		tabs.selectTabViewItem(tabs.tabViewItem(at: selectedIndex))

		let n = NotificationCenter.default
		n.addObserver(self, selector: #selector(PreferencesWindow.updateApiTable), name: ApiUsageUpdateNotification, object: nil)
		n.addObserver(self, selector: #selector(PreferencesWindow.updateImportExportSettings), name: SettingsExportedNotification, object: nil)

		deferredUpdateTimer = PopTimer(timeInterval: 0.5) { [weak self] in
			if let s = self, s.serversDirty {
				s.serversDirty = false
				DataManager.saveDB()
				Settings.possibleExport(nil)
				app.setupWindows()
			} else {
				DataManager.saveDB()
				app.updateAllMenus()
			}
		}
	}

	func updateApiTable() {
		serverList.reloadData()
	}

	deinit {
		let n = NotificationCenter.default
		n.removeObserver(serverList)
		n.removeObserver(self)
	}

	private func addTooltips() {
		snoozePresetsList.toolTip = "The list of presets that will be displayed in the snooze context menu"
		serverList.toolTip = "The list of GitHub API servers that Trailer will attempt to sync data from. You can edit each server's details from the pane on the right. Bear in mind that some servers, like the public GitHub server for instance, have strict API volume limits, and syncing too many repos or items too often can result in API usage going over the limit. You can monitor your usage from the bar next to the server's name. If it is red, you're close to maximum. Your API usage is reset every hour."
		apiServerName.toolTip = "An internal name you want to use to refer to this server."
		apiServerApiPath.toolTip = "The full URL of the root of the API endpoints for this server. The placeholder text shows examples for GitHub and GitHub Enterprise servers, but your own custom configuration may vary."
		apiServerWebPath.toolTip = "This is the root of the web front-end of your server. It is used for constructing the paths to open your watchlist and API key management links. Other than that it is not used to sync data."
		apiServerReportError.toolTip = "If this is checked, Trailer will display a red 'X' symbol on your menubar if sync fails with this server. It is usually a good idea to keep this on, but you may want to turn it off if a specific server isn't always reacahble, for instance."
		projectsTable.toolTip = "These are all your watched repositories.\n\nTrailer scans the watchlists of all the servers you have configured and adds the repositories to this combined watchlist.\n\nYou can visit and edit the watchlist of each server from the link provided on that server's entry on the 'Servers' tab.\n\nYou can keep clutter low by editing the visibility of items from each repository with the dropdown menus on the right."
		repoFilter.toolTip = "Quickly find a repository you are looking for by typing some text in there. Productivity tip: If you use the buttons on the right to set visibility of 'all' items, those settings will apply to only the visible filtered items."
		allNewPrsSetting.toolTip = "The visibility settings you would like to apply by default for Pull Requests if a new repository is added in your watchlist."
		allNewIssuesSetting.toolTip = "The visibility settings you would like to apply by default for Pull Requests if a new repository is added in your watchlist."
		refreshButton.toolTip = "Reload all watchlists now. Normally Trailer does this by itself every few hours. You can control how often from the 'Display' tab."
		launchAtStartup.toolTip = "Automatically launch Trailer when you log in."
		allPrsSetting.toolTip = "Set the PR visibility of all (or the currently selected/filtered) repositories"
		allIssuesSetting.toolTip = "Set the issue visibility of all (or the currently selected/filtered) repositories"
		allHidingSetting.toolTip = "Set the any special hiding settings of all (or the currently selected/filtered) repositories"
		showCreationDates.toolTip = Settings.showCreatedInsteadOfUpdatedHelp
		markUnmergeableOnUserSectionsOnly.toolTip = Settings.markUnmergeableOnUserSectionsOnlyHelp
		countOnlyListedItems.toolTip = Settings.countOnlyListedItemsHelp
		displayRepositoryNames.toolTip = Settings.showReposInNameHelp
		useVibrancy.toolTip = Settings.useVibrancyHelp
		hideAvatars.toolTip = Settings.hideAvatarsHelp
		showSeparateApiServersInMenu.toolTip = Settings.showSeparateApiServersInMenuHelp
		sortModeSelect.toolTip = Settings.sortMethodHelp
		sortingOrder.toolTip = Settings.sortDescendingHelp
		groupByRepo.toolTip = Settings.groupByRepoHelp
		assignedPrHandlingPolicy.toolTip = Settings.assignedPrHandlingPolicyHelp
		includeTitlesInFiltering.toolTip = Settings.includeTitlesInFilterHelp
		includeMilestonesInFiltering.toolTip = Settings.includeMilestonesInFilterHelp
		includeAssigneeNamesInFiltering.toolTip = Settings.includeAssigneeInFilterHelp
		includeLabelsInFiltering.toolTip = Settings.includeLabelsInFilterHelp
		includeRepositoriesInFiltering.toolTip = Settings.includeReposInFilterHelp
		includeServersInFiltering.toolTip = Settings.includeServersInFilterHelp
		includeStatusesInFiltering.toolTip = Settings.includeStatusesInFilterHelp
		includeUsersInFiltering.toolTip = Settings.includeUsersInFilterHelp
		includeNumbersInFiltering.toolTip = Settings.includeNumbersInFilterHelp
		grayOutWhenRefreshing.toolTip = Settings.grayOutWhenRefreshingHelp
		refreshReposLabel.toolTip = Settings.newRepoCheckPeriodHelp
		repoCheckStepper.toolTip = Settings.newRepoCheckPeriodHelp
		refreshItemsLabel.toolTip = Settings.refreshPeriodHelp
		refreshDurationStepper.toolTip = Settings.refreshPeriodHelp
		prMergedPolicy.toolTip = Settings.mergeHandlingPolicyHelp
		prClosedPolicy.toolTip = Settings.closeHandlingPolicyHelp
		dontKeepPrsMergedByMe.toolTip = Settings.dontKeepPrsMergedByMeHelp
		removeNotificationsWhenItemIsRemoved.toolTip = Settings.removeNotificationsWhenItemIsRemovedHelp
		dontConfirmRemoveAllClosed.toolTip = Settings.dontAskBeforeWipingClosedHelp
		dontConfirmRemoveAllMerged.toolTip = Settings.dontAskBeforeWipingMergedHelp
		showAllComments.toolTip = Settings.showCommentsEverywhereHelp
		hideUncommentedPrs.toolTip = Settings.hideUncommentedItemsHelp
		openPrAtFirstUnreadComment.toolTip = Settings.openPrAtFirstUnreadCommentHelp
		assumeCommentsBeforeMineAreRead.toolTip = Settings.assumeReadItemIfUserHasNewerCommentsHelp
		disableAllCommentNotifications.toolTip = Settings.disableAllCommentNotificationsHelp
		showLabels.toolTip = Settings.showLabelsHelp
		showStatusItems.toolTip = Settings.showStatusItemsHelp
		statusItemRefreshCounter.toolTip = Settings.statusItemRefreshIntervalHelp
		statusItemRescanLabel.toolTip = Settings.statusItemRefreshIntervalHelp
		labelRefreshCounter.toolTip = Settings.labelRefreshIntervalHelp
		labelRescanLabel.toolTip = Settings.labelRefreshIntervalHelp
		makeStatusItemsSelectable.toolTip = Settings.makeStatusItemsSelectableHelp
		notifyOnStatusUpdates.toolTip = Settings.notifyOnStatusUpdatesHelp
		notifyOnStatusUpdatesForAllPrs.toolTip = Settings.notifyOnStatusUpdatesForAllPrsHelp
		hidePrsThatDontPass.toolTip = Settings.hidePrsThatArentPassingHelp
		hidePrsThatDontPassOnlyInAll.toolTip = Settings.hidePrsThatDontPassOnlyInAllHelp
		statusTermMenu.toolTip = Settings.statusFilteringTermsHelp
		logActivityToConsole.toolTip = Settings.logActivityToConsoleHelp
		dumpApiResponsesToConsole.toolTip = Settings.dumpAPIResponsesInConsoleHelp
		checkForUpdatesAutomatically.toolTip = Settings.checkForUpdatesAutomaticallyHelp
		snoozeWakeOnStatusUpdate.toolTip = Settings.snoozeWakeOnStatusUpdateHelp
		snoozeWakeOnMention.toolTip = Settings.snoozeWakeOnMentionHelp
		snoozeWakeOnComment.toolTip = Settings.snoozeWakeOnCommentHelp
		hideSnoozedItems.toolTip = Settings.hideSnoozedItemsHelp
		autoSnoozeSelector.toolTip = Settings.autoSnoozeDurationHelp
		autoSnoozeLabel.toolTip = Settings.autoSnoozeDurationHelp
		newMentionMovePolicy.toolTip = Settings.newMentionMovePolicyHelp
		teamMentionMovePolicy.toolTip = Settings.teamMentionMovePolicyHelp
		newItemInOwnedRepoMovePolicy.toolTip = Settings.newItemInOwnedRepoMovePolicyHelp
	}

	private func updateAllItemSettingButtons() {

		allPrsSetting.removeAllItems()
		allIssuesSetting.removeAllItems()
		allHidingSetting.removeAllItems()

		if projectsTable.selectedRowIndexes.count > 1 {
			allPrsSetting.addItem(withTitle: "Set selected PRs...")
			allIssuesSetting.addItem(withTitle: "Set selected issues...")
			allHidingSetting.addItem(withTitle: "Set selected hiding...")
		} else if !repoFilter.stringValue.isEmpty {
			allPrsSetting.addItem(withTitle: "Set filtered PRs...")
			allIssuesSetting.addItem(withTitle: "Set filtered issues...")
			allHidingSetting.addItem(withTitle: "Set filtered hiding...")
		} else {
			allPrsSetting.addItem(withTitle: "Set all PRs...")
			allIssuesSetting.addItem(withTitle: "Set all issues...")
			allHidingSetting.addItem(withTitle: "Set all hiding...")
		}

		allPrsSetting.addItems(withTitles: RepoDisplayPolicy.labels)
		allIssuesSetting.addItems(withTitles: RepoDisplayPolicy.labels)
		allHidingSetting.addItems(withTitles: RepoHidingPolicy.labels)
	}

	func reloadSettings() {
		let firstRow = IndexSet(integer: 0)
		serverList.selectRowIndexes(firstRow, byExtendingSelection: false)
		fillServerApiFormFromSelectedServer()
		fillSnoozeFormFromSelectedPreset()

		api.updateLimitsFromServer()
		updateStatusTermPreferenceControls()
		commentAuthorBlacklist.objectValue = Settings.commentAuthorBlacklist

		setupSortMethodMenu()
		sortModeSelect.selectItem(at: Settings.sortMethod)

		prMergedPolicy.selectItem(at: Settings.mergeHandlingPolicy)
		prClosedPolicy.selectItem(at: Settings.closeHandlingPolicy)

		launchAtStartup.integerValue = StartupLaunch.isAppLoginItem() ? 1 : 0
		dontConfirmRemoveAllClosed.integerValue = Settings.dontAskBeforeWipingClosed ? 1 : 0
		displayRepositoryNames.integerValue = Settings.showReposInName ? 1 : 0
		includeRepositoriesInFiltering.integerValue = Settings.includeReposInFilter ? 1 : 0
		includeLabelsInFiltering.integerValue = Settings.includeLabelsInFilter ? 1 : 0
		includeTitlesInFiltering.integerValue = Settings.includeTitlesInFilter ? 1 : 0
		includeMilestonesInFiltering.integerValue = Settings.includeMilestonesInFilter ? 1 : 0
		includeAssigneeNamesInFiltering.integerValue = Settings.includeAssigneeNamesInFilter ? 1 : 0
		includeUsersInFiltering.integerValue = Settings.includeUsersInFilter ? 1 : 0
		includeNumbersInFiltering.integerValue = Settings.includeNumbersInFilter ? 1 : 0
		includeServersInFiltering.integerValue = Settings.includeServersInFilter ? 1 : 0
		includeStatusesInFiltering.integerValue = Settings.includeStatusesInFilter ? 1 : 0
		dontConfirmRemoveAllMerged.integerValue = Settings.dontAskBeforeWipingMerged ? 1 : 0
		hideUncommentedPrs.integerValue = Settings.hideUncommentedItems ? 1 : 0
		assumeCommentsBeforeMineAreRead.integerValue = Settings.assumeReadItemIfUserHasNewerComments ? 1 : 0
		hideAvatars.integerValue = Settings.hideAvatars ? 1 : 0
		showSeparateApiServersInMenu.integerValue = Settings.showSeparateApiServersInMenu ? 1 : 0
		dontKeepPrsMergedByMe.integerValue = Settings.dontKeepPrsMergedByMe ? 1 : 0
		removeNotificationsWhenItemIsRemoved.integerValue = Settings.removeNotificationsWhenItemIsRemoved ? 1 : 0
		grayOutWhenRefreshing.integerValue = Settings.grayOutWhenRefreshing ? 1 : 0
		notifyOnStatusUpdates.integerValue = Settings.notifyOnStatusUpdates ? 1 : 0
		notifyOnStatusUpdatesForAllPrs.integerValue = Settings.notifyOnStatusUpdatesForAllPrs ? 1 : 0
		disableAllCommentNotifications.integerValue = Settings.disableAllCommentNotifications ? 1 : 0
		showAllComments.integerValue = Settings.showCommentsEverywhere ? 1 : 0
		sortingOrder.integerValue = Settings.sortDescending ? 1 : 0
		showCreationDates.integerValue = Settings.showCreatedInsteadOfUpdated ? 1 : 0
		groupByRepo.integerValue = Settings.groupByRepo ? 1 : 0
		assignedPrHandlingPolicy.selectItem(at: Settings.assignedPrHandlingPolicy)
		showStatusItems.integerValue = Settings.showStatusItems ? 1 : 0
		makeStatusItemsSelectable.integerValue = Settings.makeStatusItemsSelectable ? 1 : 0
		markUnmergeableOnUserSectionsOnly.integerValue = Settings.markUnmergeableOnUserSectionsOnly ? 1 : 0
		countOnlyListedItems.integerValue = Settings.countOnlyListedItems ? 0 : 1
		openPrAtFirstUnreadComment.integerValue = Settings.openPrAtFirstUnreadComment ? 1 : 0
		logActivityToConsole.integerValue = Settings.logActivityToConsole ? 1 : 0
		dumpApiResponsesToConsole.integerValue = Settings.dumpAPIResponsesInConsole ? 1 : 0
		showLabels.integerValue = Settings.showLabels ? 1 : 0
		useVibrancy.integerValue = Settings.useVibrancy ? 1 : 0
		hidePrsThatDontPass.integerValue = Settings.hidePrsThatArentPassing ? 1 : 0
		hidePrsThatDontPassOnlyInAll.integerValue = Settings.hidePrsThatDontPassOnlyInAll ? 1 : 0

		hideSnoozedItems.integerValue = Settings.hideSnoozedItems ? 1 : 0

		allNewPrsSetting.selectItem(at: Settings.displayPolicyForNewPrs)
		allNewIssuesSetting.selectItem(at: Settings.displayPolicyForNewIssues)

		newMentionMovePolicy.selectItem(at: Settings.newMentionMovePolicy)
		teamMentionMovePolicy.selectItem(at: Settings.teamMentionMovePolicy)
		newItemInOwnedRepoMovePolicy.selectItem(at: Settings.newItemInOwnedRepoMovePolicy)

		hotkeyEnable.integerValue = Settings.hotkeyEnable ? 1 : 0
		hotkeyControlModifier.integerValue = Settings.hotkeyControlModifier ? 1 : 0
		hotkeyCommandModifier.integerValue = Settings.hotkeyCommandModifier ? 1 : 0
		hotkeyOptionModifier.integerValue = Settings.hotkeyOptionModifier ? 1 : 0
		hotkeyShiftModifier.integerValue = Settings.hotkeyShiftModifier ? 1 : 0

		enableHotkeySegments()

		hotkeyLetter.addItems(withTitles: ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"])
		hotkeyLetter.selectItem(withTitle: Settings.hotkeyLetter)

		refreshUpdatePreferences()
		updateStatusItemsOptions()
		updateLabelOptions()
		updateHistoryOptions()

		hotkeyEnable.isEnabled = true

		repoCheckStepper.floatValue = Settings.newRepoCheckPeriod
		newRepoCheckChanged(nil)

		refreshDurationStepper.floatValue = min(Settings.refreshPeriod, 3600)
		refreshDurationChanged(nil)

		updateImportExportSettings()

		updateActivity()
	}

	func updateActivity() {
		if appIsRefreshing {
			refreshButton.isEnabled = false
			projectsTable.isEnabled = false
			allPrsSetting.isEnabled = false
			allIssuesSetting.isEnabled = false
			activityDisplay.startAnimation(nil)
		} else {
			refreshButton.isEnabled = ApiServer.someServersHaveAuthTokens(in: mainObjectContext)
			projectsTable.isEnabled = true
			allPrsSetting.isEnabled = true
			allIssuesSetting.isEnabled = true
			activityDisplay.stopAnimation(nil)
		}
	}

	@IBAction func showLabelsSelected(_ sender: NSButton) {
		Settings.showLabels = (sender.integerValue==1)
		deferredUpdateTimer.push()
		updateLabelOptions()

		api.resetAllLabelChecks()
		if Settings.showLabels {
			ApiServer.resetSyncOfEverything()
		}
	}

	@IBAction func newMentionMovePolicySelected(_ sender: NSPopUpButton) {
		Settings.newMentionMovePolicy = sender.indexOfSelectedItem
		DataManager.postProcessAllItems()
		deferredUpdateTimer.push()
	}
	@IBAction func teamMentionMovePolicySelected(_ sender: NSPopUpButton) {
		Settings.teamMentionMovePolicy = sender.indexOfSelectedItem
		DataManager.postProcessAllItems()
		deferredUpdateTimer.push()
	}
	@IBAction func newItemInOwnedRepoMovePolicySelected(_ sender: NSPopUpButton) {
		Settings.newItemInOwnedRepoMovePolicy = sender.indexOfSelectedItem
		DataManager.postProcessAllItems()
		deferredUpdateTimer.push()
	}

	@IBAction func dontConfirmRemoveAllMergedSelected(_ sender: NSButton) {
		Settings.dontAskBeforeWipingMerged = (sender.integerValue==1)
	}

	@IBAction func markUnmergeableOnUserSectionsOnlySelected(_ sender: NSButton) {
		Settings.markUnmergeableOnUserSectionsOnly = (sender.integerValue==1)
		deferredUpdateTimer.push()
	}

	@IBAction func displayRepositoryNameSelected(_ sender: NSButton) {
		Settings.showReposInName = (sender.integerValue==1)
		deferredUpdateTimer.push()
	}

	@IBAction func useVibrancySelected(_ sender: NSButton) {
		Settings.useVibrancy = (sender.integerValue==1)
		app.updateVibrancies()
	}

	@IBAction func logActivityToConsoleSelected(_ sender: NSButton) {
		Settings.logActivityToConsole = (sender.integerValue==1)
		logActivityToConsole.integerValue = Settings.logActivityToConsole ? 1 : 0
		if Settings.logActivityToConsole {
			let alert = NSAlert()
			alert.messageText = "Warning"
			#if DEBUG
				alert.informativeText = "Sorry, logging is always active in development versions"
				#else
				alert.informativeText = "Logging is a feature meant for error reporting, having it constantly enabled will cause this app to be less responsive, use more power, and constitute a security risk"
			#endif
			alert.addButton(withTitle: "OK")
			alert.beginSheetModal(for: self, completionHandler: nil)
		}
	}

	@IBAction func dumpApiResponsesToConsoleSelected(_ sender: NSButton) {
		Settings.dumpAPIResponsesInConsole = (sender.integerValue==1)
		if Settings.dumpAPIResponsesInConsole {
			let alert = NSAlert()
			alert.messageText = "Warning"
			alert.informativeText = "This is a feature meant for error reporting, having it constantly enabled will cause this app to be less responsive, use more power, and constitute a security risk"
			alert.addButton(withTitle: "OK")
			alert.beginSheetModal(for: self, completionHandler: nil)
		}
	}

    @IBAction func includeServersInFilteringSelected(_ sender: NSButton) {
        Settings.includeServersInFilter = (sender.integerValue==1)
		deferredUpdateTimer.push()
    }

	@IBAction func includeNumbersInFilteringSelected(_ sender: NSButton) {
		Settings.includeNumbersInFilter = (sender.integerValue==1)
		deferredUpdateTimer.push()
	}

    @IBAction func includeUsersInFilteringSelected(_ sender: NSButton) {
        Settings.includeUsersInFilter = (sender.integerValue==1)
		deferredUpdateTimer.push()
    }

	@IBAction func includeLabelsInFilteringSelected(_ sender: NSButton) {
		Settings.includeLabelsInFilter = (sender.integerValue==1)
		deferredUpdateTimer.push()
	}

	@IBAction func includeStatusesInFilteringSelected(_ sender: NSButton) {
		Settings.includeStatusesInFilter = (sender.integerValue==1)
		deferredUpdateTimer.push()
	}

	@IBAction func includeTitlesInFilteringSelected(_ sender: NSButton) {
		Settings.includeTitlesInFilter = (sender.integerValue==1)
		deferredUpdateTimer.push()
	}

	@IBAction func includeMilestonesInFilteringSelected(_ sender: NSButton) {
		Settings.includeMilestonesInFilter = (sender.integerValue==1)
		deferredUpdateTimer.push()
	}

	@IBAction func includeAssigneeNamesInFilteringSelected(_ sender: NSButton) {
		Settings.includeAssigneeNamesInFilter = (sender.integerValue==1)
		deferredUpdateTimer.push()
	}

	@IBAction func includeRepositoriesInfilterSelected(_ sender: NSButton) {
		Settings.includeReposInFilter = (sender.integerValue==1)
		deferredUpdateTimer.push()
	}

	@IBAction func dontConfirmRemoveAllClosedSelected(_ sender: NSButton) {
		Settings.dontAskBeforeWipingClosed = (sender.integerValue==1)
	}

	@IBAction func assumeAllCommentsBeforeMineAreReadSelected(_ sender: NSButton) {
		Settings.assumeReadItemIfUserHasNewerComments = (sender.integerValue==1)
		DataManager.postProcessAllItems()
		deferredUpdateTimer.push()
	}

	@IBAction func removeNotificationsWhenItemIsRemovedSelected(_ sender: NSButton) {
		Settings.removeNotificationsWhenItemIsRemoved = (sender.integerValue==1)
	}

	@IBAction func dontKeepMyPrsSelected(_ sender: NSButton) {
		Settings.dontKeepPrsMergedByMe = (sender.integerValue==1)
		updateHistoryOptions()
	}

	private func updateHistoryOptions() {
		dontKeepPrsMergedByMe.isEnabled = Settings.mergeHandlingPolicy != HandlingPolicy.keepNone.rawValue
	}

	@IBAction func grayOutWhenRefreshingSelected(_ sender: NSButton) {
		Settings.grayOutWhenRefreshing = (sender.integerValue==1)
	}

	@IBAction func disableAllCommentNotificationsSelected(_ sender: NSButton) {
		Settings.disableAllCommentNotifications = (sender.integerValue==1)
	}

	@IBAction func notifyOnStatusUpdatesSelected(_ sender: NSButton) {
		Settings.notifyOnStatusUpdates = (sender.integerValue==1)
		updateStatusItemsOptions()
	}

	@IBAction func notifyOnStatusUpdatesOnAllPrsSelected(_ sender: NSButton) {
		Settings.notifyOnStatusUpdatesForAllPrs = (sender.integerValue==1)
	}

	@IBAction func hidePrsThatDontPassOnlyInAllSelected(_ sender: NSButton) {
		Settings.hidePrsThatDontPassOnlyInAll = (sender.integerValue==1)
		DataManager.postProcessAllItems()
		deferredUpdateTimer.push()
	}

	@IBAction func hidePrsThatDontPassSelected(_ sender: NSButton) {
		Settings.hidePrsThatArentPassing = (sender.integerValue==1)
		updateStatusItemsOptions()
		DataManager.postProcessAllItems()
		deferredUpdateTimer.push()
	}

	@IBAction func hideAvatarsSelected(_ sender: NSButton) {
		Settings.hideAvatars = (sender.integerValue==1)
		DataManager.postProcessAllItems()
		deferredUpdateTimer.push()
	}

	@IBAction func showSeparateApiServersInMenuSelected(_ sender: NSButton) {
		Settings.showSeparateApiServersInMenu = (sender.integerValue==1)
		serversDirty = true
		deferredUpdateTimer.push()
	}

	private func affectedReposFromSelection() -> [Repo] {
		let selectedRows = projectsTable.selectedRowIndexes
		var affectedRepos = [Repo]()
		if selectedRows.count > 1 {
			for row in selectedRows {
				if !tableView(projectsTable, isGroupRow: row) {
					affectedRepos.append(repoForRow(row))
				}
			}
		} else {
			affectedRepos = Repo.reposForFilter(repoFilter.stringValue)
		}
		return affectedRepos
	}

	@IBAction func allPrsPolicySelected(_ sender: NSPopUpButton) {
		let index = Int64(sender.indexOfSelectedItem - 1)
		if index < 0 { return }

		for r in affectedReposFromSelection() {
			r.displayPolicyForPrs = index
			if index != RepoDisplayPolicy.hide.rawValue { r.resetSyncState() }
		}
		projectsTable.reloadData()
		sender.selectItem(at: 0)
		updateDisplayIssuesSetting()
	}

	@IBAction func allIssuesPolicySelected(_ sender: NSPopUpButton) {
		let index = Int64(sender.indexOfSelectedItem - 1)
		if index < 0 { return }

		for r in affectedReposFromSelection() {
			r.displayPolicyForIssues = index
			if index != RepoDisplayPolicy.hide.rawValue { r.resetSyncState() }
		}
		projectsTable.reloadData()
		sender.selectItem(at: 0)
		updateDisplayIssuesSetting()
	}

	@IBAction func allHidingPolicySelected(_ sender: NSPopUpButton) {
		let index = Int64(sender.indexOfSelectedItem - 1)
		if index < 0 { return }

		for r in affectedReposFromSelection() {
			r.itemHidingPolicy = index
		}
		projectsTable.reloadData()
		sender.selectItem(at: 0)
		updateDisplayIssuesSetting()
	}

	private func updateDisplayIssuesSetting() {
		DataManager.postProcessAllItems()
		preferencesDirty = true
		serversDirty = true
		deferredUpdateTimer.push()
	}

	@IBAction func allNewPrsPolicySelected(_ sender: NSPopUpButton) {
		Settings.displayPolicyForNewPrs = sender.indexOfSelectedItem
	}

	@IBAction func allNewIssuesPolicySelected(_ sender: NSPopUpButton) {
		Settings.displayPolicyForNewIssues = sender.indexOfSelectedItem
	}

	@IBAction func hideUncommentedRequestsSelected(_ sender: NSButton) {
		Settings.hideUncommentedItems = (sender.integerValue==1)
		DataManager.postProcessAllItems()
		deferredUpdateTimer.push()
	}

	@IBAction func showAllCommentsSelected(_ sender: NSButton) {
		Settings.showCommentsEverywhere = (sender.integerValue==1)
		DataManager.postProcessAllItems()
		deferredUpdateTimer.push()
	}

	@IBAction func sortOrderSelected(_ sender: NSButton) {
		Settings.sortDescending = (sender.integerValue==1)
		setupSortMethodMenu()
		DataManager.postProcessAllItems()
		deferredUpdateTimer.push()
	}

	@IBAction func countOnlyListedItemsSelected(_ sender: NSButton) {
		Settings.countOnlyListedItems = (sender.integerValue==0)
		DataManager.postProcessAllItems()
		deferredUpdateTimer.push()
	}

	@IBAction func openPrAtFirstUnreadCommentSelected(_ sender: NSButton) {
		Settings.openPrAtFirstUnreadComment = (sender.integerValue==1)
	}

	@IBAction func sortMethodChanged(_ sender: AnyObject) {
		Settings.sortMethod = sortModeSelect.indexOfSelectedItem
		DataManager.postProcessAllItems()
		deferredUpdateTimer.push()
	}

	@IBAction func showStatusItemsSelected(_ sender: NSButton) {
		Settings.showStatusItems = (sender.integerValue==1)
		deferredUpdateTimer.push()
		updateStatusItemsOptions()

		api.resetAllStatusChecks()
		if Settings.showStatusItems {
			ApiServer.resetSyncOfEverything()
		}
	}

	private func setupSortMethodMenu() {
		let m = NSMenu(title: "Sorting")
		for t in Settings.sortDescending ? SortingMethod.reverseTitles : SortingMethod.normalTitles {
			m.addItem(withTitle: t, action: #selector(PreferencesWindow.sortMethodChanged(_:)), keyEquivalent: "")
		}
		sortModeSelect.menu = m
		sortModeSelect.selectItem(at: Settings.sortMethod)
	}

	private func updateStatusItemsOptions() {
		let enable = Settings.showStatusItems
		makeStatusItemsSelectable.isEnabled = enable
		notifyOnStatusUpdates.isEnabled = enable
		notifyOnStatusUpdatesForAllPrs.isEnabled = enable
		statusTermMenu.isEnabled = enable
		statusItemRefreshCounter.isEnabled = enable
		statusItemRescanLabel.alphaValue = enable ? 1.0 : 0.5
		statusItemsRefreshNote.alphaValue = enable ? 1.0 : 0.5
		hidePrsThatDontPass.alphaValue = enable ? 1.0 : 0.5
		hidePrsThatDontPass.isEnabled = enable
		hidePrsThatDontPassOnlyInAll.isEnabled = enable && Settings.hidePrsThatArentPassing
		notifyOnStatusUpdatesForAllPrs.isEnabled = enable && Settings.notifyOnStatusUpdates

		let count = Settings.statusItemRefreshInterval
		statusItemRefreshCounter.integerValue = count
		statusItemRescanLabel.stringValue = count>1 ? "...and re-scan once every \(count) refreshes" : "...and re-scan on every refresh"

		updateStatusTermPreferenceControls()
	}

	private func updateLabelOptions() {
		let enable = Settings.showLabels
		labelRefreshCounter.isEnabled = enable
		labelRescanLabel.alphaValue = enable ? 1.0 : 0.5
		labelRefreshNote.alphaValue = enable ? 1.0 : 0.5

		let count = Settings.labelRefreshInterval
		labelRefreshCounter.integerValue = count
		labelRescanLabel.stringValue = count>1 ? "...and re-scan once every \(count) refreshes" : "...and re-scan on every refresh"
	}

	@IBAction func labelRefreshCounterChanged(_ sender: NSStepper) {
		Settings.labelRefreshInterval = labelRefreshCounter.integerValue
		updateLabelOptions()
	}

	@IBAction func statusItemRefreshCountChanged(_ sender: NSStepper) {
		Settings.statusItemRefreshInterval = statusItemRefreshCounter.integerValue
		updateStatusItemsOptions()
	}

	@IBAction func makeStatusItemsSelectableSelected(_ sender: NSButton) {
		Settings.makeStatusItemsSelectable = (sender.integerValue==1)
		deferredUpdateTimer.push()
	}

	@IBAction func showCreationSelected(_ sender: NSButton) {
		Settings.showCreatedInsteadOfUpdated = (sender.integerValue==1)
		DataManager.postProcessAllItems()
		deferredUpdateTimer.push()
	}

	@IBAction func groupbyRepoSelected(_ sender: NSButton) {
		Settings.groupByRepo = (sender.integerValue==1)
		deferredUpdateTimer.push()
	}

	@IBAction func assignedPrHandlingPolicySelected(_ sender: NSPopUpButton) {
		Settings.assignedPrHandlingPolicy = sender.indexOfSelectedItem
		DataManager.postProcessAllItems()
		deferredUpdateTimer.push()
	}

	@IBAction func checkForUpdatesAutomaticallySelected(_ sender: NSButton) {
		Settings.checkForUpdatesAutomatically = (sender.integerValue==1)
		refreshUpdatePreferences()
	}

	private func refreshUpdatePreferences() {
		let setting = Settings.checkForUpdatesAutomatically
		let interval = Settings.checkForUpdatesInterval

		checkForUpdatesLabel.isHidden = !setting
		checkForUpdatesSelector.isHidden = !setting

		checkForUpdatesSelector.integerValue = interval
		checkForUpdatesAutomatically.integerValue = setting ? 1 : 0
		checkForUpdatesLabel.stringValue = interval<2 ? "Check every hour" : "Check every \(interval) hours"
	}

	@IBAction func checkForUpdatesIntervalChanged(_ sender: NSStepper) {
		Settings.checkForUpdatesInterval = sender.integerValue
		refreshUpdatePreferences()
	}

	@IBAction func launchAtStartSelected(_ sender: NSButton) {
		StartupLaunch.setLaunchOnLogin(sender.integerValue==1)
	}

	@IBAction func refreshReposSelected(_ sender: NSButton?) {
		app.prepareForRefresh()

		let tempContext = DataManager.childContext()
		api.fetchRepositories(to: tempContext) {

			if ApiServer.shouldReportRefreshFailure(in: tempContext) {
				var errorServers = [String]()
				for apiServer in ApiServer.allApiServers(in: tempContext) {
					if apiServer.goodToGo && !apiServer.lastSyncSucceeded {
						errorServers.append(S(apiServer.label))
					}
				}

				let serverNames = errorServers.joined(separator: ", ")

				let alert = NSAlert()
				alert.messageText = "Error"
				alert.informativeText = "Could not refresh repository list from \(serverNames), please ensure that the tokens you are using are valid"
				alert.addButton(withTitle: "OK")
				alert.runModal()
			} else {
				do {
					try tempContext.save()
				} catch {
				}
			}
			app.completeRefresh()
		}
	}

	private func selectedServer() -> ApiServer? {
		let selected = serverList.selectedRow
		if selected >= 0 {
			return ApiServer.allApiServers(in: mainObjectContext)[selected]
		}
		return nil
	}

	@IBAction func deleteSelectedServerSelected(_ sender: NSButton) {
		if let selectedServer = selectedServer(), let index = ApiServer.allApiServers(in: mainObjectContext).index(of: selectedServer) {
			mainObjectContext.delete(selectedServer)
			serverList.reloadData()
			serverList.selectRowIndexes(IndexSet(integer: min(index, serverList.numberOfRows-1)), byExtendingSelection: false)
			fillServerApiFormFromSelectedServer()
			serversDirty = true
			deferredUpdateTimer.push()
		}
	}

	@IBAction func apiServerReportErrorSelected(_ sender: NSButton) {
		if let apiServer = selectedServer() {
			apiServer.reportRefreshFailures = (sender.integerValue != 0)
			storeApiFormToSelectedServer()
		}
	}

	func updateImportExportSettings() {
		repeatLastExportAutomatically.integerValue = Settings.autoRepeatSettingsExport ? 1 : 0
		if let lastExportDate = Settings.lastExportDate, let fileName = Settings.lastExportUrl?.absoluteString, let unescapedName = fileName.removingPercentEncoding {
			let time = itemDateFormatter.string(from: lastExportDate)
			lastExportReport.stringValue = "Last exported \(time) to \(unescapedName)"
		} else {
			lastExportReport.stringValue = ""
		}
	}

	@IBAction func repeatLastExportSelected(_ sender: AnyObject) {
		Settings.autoRepeatSettingsExport = (repeatLastExportAutomatically.integerValue==1)
	}

	@IBAction func exportCurrentSettingsSelected(_ sender: NSButton) {
		let s = NSSavePanel()
		s.title = "Export Current Settings..."
		s.prompt = "Export"
		s.nameFieldLabel = "Settings File"
		s.message = "Export Current Settings..."
		s.isExtensionHidden = false
		s.nameFieldStringValue = "Trailer Settings"
		s.allowedFileTypes = ["trailerSettings"]
		s.beginSheetModal(for: self) { response in
			if response == NSFileHandlingPanelOKButton, let url = s.url {
				_ = Settings.writeToURL(url)
				DLog("Exported settings to %@", url.absoluteString)
			}
		}
	}

	@IBAction func importSettingsSelected(_ sender: NSButton) {
		let o = NSOpenPanel()
		o.title = "Import Settings From File..."
		o.prompt = "Import"
		o.nameFieldLabel = "Settings File"
		o.message = "Import Settings From File..."
		o.isExtensionHidden = false
		o.allowedFileTypes = ["trailerSettings"]
		o.beginSheetModal(for: self) { response in
			if response == NSFileHandlingPanelOKButton, let url = o.url {
				atNextEvent {
					_ = app.tryLoadSettings(url, skipConfirm: Settings.dontConfirmSettingsImport)
				}
			}
		}
	}

	private func colorButton(_ button: NSButton, withColor: NSColor) {
		let title = button.attributedTitle.mutableCopy() as! NSMutableAttributedString
		title.addAttribute(NSForegroundColorAttributeName, value: withColor, range: NSMakeRange(0, title.length))
		button.attributedTitle = title
	}

	private func enableHotkeySegments() {
		if Settings.hotkeyEnable {
			colorButton(hotkeyCommandModifier, withColor: Settings.hotkeyCommandModifier ? NSColor.controlTextColor : NSColor.disabledControlTextColor)
			colorButton(hotkeyControlModifier, withColor: Settings.hotkeyControlModifier ? NSColor.controlTextColor : NSColor.disabledControlTextColor)
			colorButton(hotkeyOptionModifier, withColor: Settings.hotkeyOptionModifier ? NSColor.controlTextColor : NSColor.disabledControlTextColor)
			colorButton(hotkeyShiftModifier, withColor: Settings.hotkeyShiftModifier ? NSColor.controlTextColor : NSColor.disabledControlTextColor)
		}
		hotKeyContainer.isHidden = !Settings.hotkeyEnable
		hotKeyHelp.isHidden = Settings.hotkeyEnable
	}

	@IBAction func enableHotkeySelected(_ sender: AnyObject) {
		Settings.hotkeyEnable = hotkeyEnable.integerValue != 0
		Settings.hotkeyLetter = hotkeyLetter.titleOfSelectedItem ?? "T"
		Settings.hotkeyControlModifier = hotkeyControlModifier.integerValue != 0
		Settings.hotkeyCommandModifier = hotkeyCommandModifier.integerValue != 0
		Settings.hotkeyOptionModifier = hotkeyOptionModifier.integerValue != 0
		Settings.hotkeyShiftModifier = hotkeyShiftModifier.integerValue != 0
		enableHotkeySegments()
		app.addHotKeySupport()
	}

	private func reportNeedFrontEnd() {
		let alert = NSAlert()
		alert.messageText = "Please provide a full URL for the web front end of this server first"
		alert.addButton(withTitle: "OK")
		alert.runModal()
	}

	@IBAction func createTokenSelected(_ sender: NSButton) {
		if apiServerWebPath.stringValue.isEmpty {
			reportNeedFrontEnd()
		} else {
			let address = "\(apiServerWebPath.stringValue)/settings/tokens/new"
			NSWorkspace.shared().open(URL(string: address)!)
		}
	}

	@IBAction func viewExistingTokensSelected(_ sender: NSButton) {
		if apiServerWebPath.stringValue.isEmpty {
			reportNeedFrontEnd()
		} else {
			let address = "\(apiServerWebPath.stringValue)/settings/applications"
			NSWorkspace.shared().open(URL(string: address)!)
		}
	}

	@IBAction func viewWatchlistSelected(_ sender: NSButton) {
		if apiServerWebPath.stringValue.isEmpty {
			reportNeedFrontEnd()
		} else {
			let address = "\(apiServerWebPath.stringValue)/watching"
			NSWorkspace.shared().open(URL(string: address)!)
		}
	}

	@IBAction func prMergePolicySelected(_ sender: NSPopUpButton) {
		Settings.mergeHandlingPolicy = sender.indexOfSelectedItem
		updateHistoryOptions()
	}

	@IBAction func prClosePolicySelected(_ sender: NSPopUpButton) {
		Settings.closeHandlingPolicy = sender.indexOfSelectedItem
	}

	private func updateStatusTermPreferenceControls() {
		let mode = Settings.statusFilteringMode
		statusTermMenu.selectItem(at: mode)
		if mode != 0 {
			statusTermsField.isEnabled = true
			statusTermsField.alphaValue = 1.0
		}
		else
		{
			statusTermsField.isEnabled = false
			statusTermsField.alphaValue = 0.5
		}
		statusTermsField.objectValue = Settings.statusFilteringTerms
	}

	@IBAction func statusFilterMenuChanged(_ sender: NSPopUpButton) {
		Settings.statusFilteringMode = sender.indexOfSelectedItem
		Settings.statusFilteringTerms = statusTermsField.objectValue as! [String]
		updateStatusTermPreferenceControls()
		deferredUpdateTimer.push()
	}

	@IBAction func testApiServerSelected(_ sender: NSButton) {
		sender.isEnabled = false
		let apiServer = selectedServer()!
		api.testApi(to: apiServer) { error in
			let alert = NSAlert()
			if let e = error {
				alert.messageText = "The test failed for \(S(apiServer.apiPath))"
				alert.informativeText = e.localizedDescription
			} else {
				alert.messageText = "This API server seems OK!"
			}
			alert.addButton(withTitle: "OK")
			alert.runModal()
			sender.isEnabled = true
		}
	}

	@IBAction func apiRestoreDefaultsSelected(_ sender: NSButton)
	{
		if let apiServer = selectedServer() {
			apiServer.resetToGithub()
			fillServerApiFormFromSelectedServer()
			storeApiFormToSelectedServer()
		}
	}

	private func fillServerApiFormFromSelectedServer() {
		if let apiServer = selectedServer() {
			apiServerName.stringValue = S(apiServer.label)
			apiServerWebPath.stringValue = S(apiServer.webPath)
			apiServerApiPath.stringValue = S(apiServer.apiPath)
			apiServerAuthToken.stringValue = S(apiServer.authToken)
			apiServerSelectedBox.title = apiServer.label ?? "New Server"
			apiServerTestButton.isEnabled = !S(apiServer.authToken).isEmpty
			apiServerDeleteButton.isEnabled = (ApiServer.countApiServers(in: mainObjectContext) > 1)
			apiServerReportError.integerValue = apiServer.reportRefreshFailures ? 1 : 0
		}
	}

	private func storeApiFormToSelectedServer() {
		if let apiServer = selectedServer() {
			apiServer.label = apiServerName.stringValue
			apiServer.apiPath = apiServerApiPath.stringValue
			apiServer.webPath = apiServerWebPath.stringValue
			apiServer.authToken = apiServerAuthToken.stringValue
			apiServerTestButton.isEnabled = !S(apiServer.authToken).isEmpty
			serverList.reloadData()
			serversDirty = true
			deferredUpdateTimer.push()
		}
	}

	@IBAction func addNewApiServerSelected(_ sender: NSButton) {
		let a = ApiServer.insertNewServer(in: mainObjectContext)
		a.label = "New API Server"
		serverList.reloadData()
		if let index = ApiServer.allApiServers(in: mainObjectContext).index(of: a) {
			serverList.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
			fillServerApiFormFromSelectedServer()
		}
		serversDirty = true
		deferredUpdateTimer.push()
	}

	@IBAction func refreshDurationChanged(_ sender: NSStepper?) {
		Settings.refreshPeriod = refreshDurationStepper.floatValue
		refreshDurationLabel.stringValue = "Refresh items every \(refreshDurationStepper.integerValue) seconds"
	}

	@IBAction func newRepoCheckChanged(_ sender: NSStepper?) {
		Settings.newRepoCheckPeriod = repoCheckStepper.floatValue
		repoCheckLabel.stringValue = "Refresh repos & teams every \(repoCheckStepper.integerValue) hours"
	}

	func windowWillClose(_ notification: Notification) {
		if ApiServer.someServersHaveAuthTokens(in: mainObjectContext) && preferencesDirty {
			app.startRefresh()
		} else {
			if app.refreshTimer == nil && Settings.refreshPeriod > 0.0 {
				app.startRefreshIfItIsDue()
			}
		}
		app.setUpdateCheckParameters()
		app.closedPreferencesWindow()
	}

	override func controlTextDidChange(_ n: Notification) {
		if let obj: AnyObject = n.object {

			if obj===apiServerName {
				if let apiServer = selectedServer() {
					apiServer.label = apiServerName.stringValue
					storeApiFormToSelectedServer()
				}
			} else if obj===apiServerApiPath {
				if let apiServer = selectedServer() {
					apiServer.apiPath = apiServerApiPath.stringValue
					storeApiFormToSelectedServer()
					apiServer.clearAllRelatedInfo()
					reset()
				}
			} else if obj===apiServerWebPath {
				if let apiServer = selectedServer() {
					apiServer.webPath = apiServerWebPath.stringValue
					storeApiFormToSelectedServer()
				}
			} else if obj===apiServerAuthToken {
				if let apiServer = selectedServer() {
					apiServer.authToken = apiServerAuthToken.stringValue
					storeApiFormToSelectedServer()
					apiServer.clearAllRelatedInfo()
					reset()
				}
			} else if obj===repoFilter {
				projectsTable.reloadData()
				updateAllItemSettingButtons()
			} else if obj===statusTermsField {
				let existingTokens = Settings.statusFilteringTerms
				let newTokens = statusTermsField.objectValue as! [String]
				if existingTokens != newTokens {
					Settings.statusFilteringTerms = newTokens
					deferredUpdateTimer.push()
				}
			} else if obj===commentAuthorBlacklist {
				let existingTokens = Settings.commentAuthorBlacklist
				let newTokens = commentAuthorBlacklist.objectValue as! [String]
				if existingTokens != newTokens {
					Settings.commentAuthorBlacklist = newTokens
				}
			}
		}
	}

	///////////// Tabs

	func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?) {
		if let item = tabViewItem {
			let newIndex = tabView.indexOfTabViewItem(item)
			if newIndex == 1 {
				if lastRepoCheck == Date.distantPast && DataManager.appIsConfigured {
					refreshReposSelected(nil)
				}
			}
			Settings.lastPreferencesTabSelectedOSX = newIndex
		}
	}

	///////////// Repo table

	func tableViewSelectionDidChange(_ notification: Notification) {
		if serverList === notification.object {
			fillServerApiFormFromSelectedServer()
		} else if projectsTable === notification.object {
			updateAllItemSettingButtons()
		} else if snoozePresetsList === notification.object {
			fillSnoozeFormFromSelectedPreset()
		}
	}

	private func repoForRow(_ row: Int) -> Repo {
		let parentCount = Repo.countParentRepos(repoFilter.stringValue)
		var r = row
		if r > parentCount {
			r -= 1
		}
		let filteredRepos = Repo.reposForFilter(repoFilter.stringValue)
		return filteredRepos[r-1]
	}

	func tableView(_ tv: NSTableView, shouldSelectRow row: Int) -> Bool {
		return !tableView(tv, isGroupRow:row)
	}

	func tableView(_ tv: NSTableView, willDisplayCell c: AnyObject, for tableColumn: NSTableColumn?, row: Int) {
		let cell = c as! NSCell
		if tv === projectsTable {
			if tableColumn?.identifier == "repos" {
				if tableView(tv, isGroupRow:row) {
					cell.title = row==0 ? "Parent Repositories" : "Forked Repositories"
					cell.isEnabled = false
				} else {
					cell.isEnabled = true
					let r = repoForRow(row)
					let repoName = S(r.fullName)
					let title = r.inaccessible ? "\(repoName) (inaccessible)" : repoName
					let textColor = (row == tv.selectedRow) ? NSColor.selectedControlTextColor : (r.shouldSync ? NSColor.textColor : NSColor.textColor.withAlphaComponent(0.4))
					cell.attributedStringValue = NSAttributedString(string: title, attributes: [NSForegroundColorAttributeName: textColor])
				}
			} else {
				if let menuCell = cell as? NSTextFieldCell {
					if tableColumn?.identifier == "group" {
						if tableView(tv, isGroupRow:row) {
							menuCell.stringValue = ""
							menuCell.placeholderString = nil
							menuCell.isEnabled = false
						} else {
							let r = repoForRow(row)
							menuCell.isEnabled = true
							menuCell.placeholderString = "None"
							menuCell.stringValue = S(r.groupLabel)
						}
					}
				} else if let menuCell = cell as? NSPopUpButtonCell {
					menuCell.removeAllItems()
					if tableView(tv, isGroupRow:row) {
						menuCell.selectItem(at: -1)
						menuCell.isEnabled = false
						menuCell.arrowPosition = .noArrow
					} else {
						let r = repoForRow(row)
						menuCell.isEnabled = true
						menuCell.arrowPosition = .arrowAtBottom

						var count = 0
						let fontSize = NSFont.systemFontSize(for: .small)
						if tableColumn?.identifier == "hide" {
							for policy in RepoHidingPolicy.policies {
								let m = NSMenuItem()
								m.attributedTitle = NSAttributedString(string: policy.name(), attributes: [
									NSFontAttributeName: count==0 ? NSFont.systemFont(ofSize: fontSize) : NSFont.boldSystemFont(ofSize: fontSize),
									NSForegroundColorAttributeName: policy.color(),
									])
								menuCell.menu?.addItem(m)
								count += 1
							}
							menuCell.selectItem(at: Int(r.itemHidingPolicy))
						} else {
							for policy in RepoDisplayPolicy.policies {
								let m = NSMenuItem()
								m.attributedTitle = NSAttributedString(string: policy.name(), attributes: [
									NSFontAttributeName: count==0 ? NSFont.systemFont(ofSize: fontSize) : NSFont.boldSystemFont(ofSize: fontSize),
									NSForegroundColorAttributeName: policy.color(),
									])
								menuCell.menu?.addItem(m)
								count += 1
							}
							let selectedIndex = Int(tableColumn?.identifier == "prs" ? r.displayPolicyForPrs : r.displayPolicyForIssues)
							menuCell.selectItem(at: selectedIndex)
						}
					}
				}
			}
		} else if tv == serverList {
			let allServers = ApiServer.allApiServers(in: mainObjectContext)
			let apiServer = allServers[row]
			if tableColumn?.identifier == "server" {
				cell.title = S(apiServer.label)
				let tc = c as! NSTextFieldCell
				if apiServer.lastSyncSucceeded {
					tc.textColor = NSColor.textColor
				} else {
					tc.textColor = NSColor.red
				}
			} else { // api usage
				let c = cell as! NSLevelIndicatorCell
				c.minValue = 0
				let rl = Double(apiServer.requestsLimit)
				c.maxValue = rl
				c.warningValue = rl*0.5
				c.criticalValue = rl*0.8
				c.doubleValue = rl - Double(apiServer.requestsRemaining)
			}
		} else if tv == snoozePresetsList {
			let allPresets = SnoozePreset.allSnoozePresets(in: mainObjectContext)
			let preset = allPresets[row]
			cell.title = preset.listDescription
			let tc = c as! NSTextFieldCell
			tc.textColor = NSColor.textColor
		}
	}

	func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
		if tableView === projectsTable {
			return (row == 0 || row == Repo.countParentRepos(repoFilter.stringValue) + 1)
		} else {
			return false
		}
	}

	func numberOfRows(in tableView: NSTableView) -> Int {
		if tableView === projectsTable {
			return Repo.reposForFilter(repoFilter.stringValue).count + 2
		} else if tableView === serverList {
			return ApiServer.countApiServers(in: mainObjectContext)
		} else if tableView === snoozePresetsList {
			return SnoozePreset.allSnoozePresets(in: mainObjectContext).count
		}
		return 0
	}

	func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		return nil
	}

	func tableView(_ tv: NSTableView, setObjectValue object: AnyObject?, for tableColumn: NSTableColumn?, row: Int) {
		if tv === projectsTable {
			if !tableView(tv, isGroupRow: row) {
				let r = repoForRow(row)
				if tableColumn?.identifier == "group" {
					let g = S(object as? String)
					r.groupLabel = g.isEmpty ? nil : g
					serversDirty = true
					deferredUpdateTimer.push()
				} else if let index = (object as? NSNumber)?.int64Value {
					if tableColumn?.identifier == "prs" {
						r.displayPolicyForPrs = index
					} else if tableColumn?.identifier == "issues" {
						r.displayPolicyForIssues = index
					} else if tableColumn?.identifier == "hide" {
						r.itemHidingPolicy = index
					}
					if index != RepoDisplayPolicy.hide.rawValue {
						r.resetSyncState()
					}
					updateDisplayIssuesSetting()
				}
			}
		}
	}

	/////////////////////////////// snoozing

	@IBAction func snoozeWakeChanged(_ sender: NSButton) {
		if let preset = selectedSnoozePreset() {
			preset.wakeOnComment = snoozeWakeOnComment.integerValue == 1
			preset.wakeOnMention = snoozeWakeOnMention.integerValue == 1
			preset.wakeOnStatusChange = snoozeWakeOnStatusUpdate.integerValue == 1
			snoozePresetsList.reloadData()
			deferredUpdateTimer.push()
		}
	}

	@IBAction func hideSnoozedItemsChanged(_ sender: NSButton) {
		Settings.hideSnoozedItems = hideSnoozedItems.integerValue == 1
		deferredUpdateTimer.push()
	}

	private func fillSnoozingDropdowns() {
		snoozeDurationDays.addItem(withTitle: "No Days")
		snoozeDurationHours.addItem(withTitle: "No Hours")
		snoozeDurationMinutes.addItem(withTitle: "No Minutes")

		snoozeDurationDays.addItem(withTitle: "1 Day")
		snoozeDurationHours.addItem(withTitle: "1 Hour")
		snoozeDurationMinutes.addItem(withTitle: "1 Minute")

		var titles = [String]()

		for f in 2..<400 {
			titles.append("\(f) Days")
		}
		snoozeDurationDays.addItems(withTitles: titles)
		titles.removeAll()
		for f in 2..<24 {
			titles.append("\(f) Hours")
		}
		snoozeDurationHours.addItems(withTitles: titles)
		titles.removeAll()
		for f in 2..<60 {
			titles.append("\(f) Minutes")
		}
		snoozeDurationMinutes.addItems(withTitles: titles)
		titles.removeAll()

		snoozeDateTimeDay.addItems(withTitles: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
		for f in 0..<24 {
			titles.append(String(format: "%02d", f))
		}
		snoozeDateTimeHour.addItems(withTitles: titles)
		titles.removeAll()
		for f in 0..<60 {
			titles.append(String(format: "%02d", f))
		}
		snoozeDateTimeMinute.addItems(withTitles: titles)

		if Settings.autoSnoozeDuration == 0 {
			autoSnoozeLabel.stringValue = "Do not auto-snooze items"
			autoSnoozeLabel.textColor = NSColor.disabledControlTextColor
		} else if Settings.autoSnoozeDuration == 1 {
			autoSnoozeLabel.stringValue = "Automatically snooze any item that has been idle for longer than a day"
			autoSnoozeLabel.textColor = NSColor.controlTextColor
		} else {
			autoSnoozeLabel.stringValue = "Automatically snooze any item that has been idle for longer than \(Settings.autoSnoozeDuration) days"
			autoSnoozeLabel.textColor = NSColor.controlTextColor
		}
		autoSnoozeSelector.integerValue = Settings.autoSnoozeDuration
	}

	@IBAction func autoSnoozeDurationChanged(_ sender: NSStepper) {
		Settings.autoSnoozeDuration = sender.integerValue
		fillSnoozingDropdowns()
		for p in DataItem.allItems(ofType: "PullRequest", in: mainObjectContext) as! [PullRequest] {
			p.wakeIfAutoSnoozed()
		}
		for i in DataItem.allItems(ofType: "Issue", in: mainObjectContext) as! [Issue] {
			i.wakeIfAutoSnoozed()
		}
		DataManager.postProcessAllItems()
		deferredUpdateTimer.push()
	}

	func selectedSnoozePreset() -> SnoozePreset? {
		let selected = snoozePresetsList.selectedRow
		if selected >= 0 {
			return SnoozePreset.allSnoozePresets(in: mainObjectContext)[selected]
		}
		return nil
	}

	func fillSnoozeFormFromSelectedPreset() {
		if let s = selectedSnoozePreset() {
			if s.duration {
				snoozeTypeDuration.integerValue = 1
				snoozeTypeDateTime.integerValue = 0
				snoozeDurationMinutes.isEnabled = true
				snoozeDurationHours.isEnabled = true
				snoozeDurationDays.isEnabled = true
				snoozeDurationMinutes.selectItem(at: Int(s.minute))
				snoozeDurationHours.selectItem(at: Int(s.hour))
				snoozeDurationDays.selectItem(at: Int(s.day))
				snoozeDateTimeMinute.isEnabled = false
				snoozeDateTimeMinute.selectItem(at: 0)
				snoozeDateTimeHour.isEnabled = false
				snoozeDateTimeHour.selectItem(at: 0)
				snoozeDateTimeDay.isEnabled = false
				snoozeDateTimeDay.selectItem(at: 0)
			} else {
				snoozeTypeDuration.integerValue = 0
				snoozeTypeDateTime.integerValue = 1
				snoozeDurationMinutes.isEnabled = false
				snoozeDurationMinutes.selectItem(at: 0)
				snoozeDurationHours.isEnabled = false
				snoozeDurationHours.selectItem(at: 0)
				snoozeDurationDays.isEnabled = false
				snoozeDurationDays.selectItem(at: 0)
				snoozeDateTimeMinute.isEnabled = true
				snoozeDateTimeHour.isEnabled = true
				snoozeDateTimeDay.isEnabled = true
				snoozeDateTimeMinute.selectItem(at: Int(s.minute))
				snoozeDateTimeHour.selectItem(at: Int(s.hour))
				snoozeDateTimeDay.selectItem(at: Int(s.day))
			}
			snoozeWakeOnComment.isEnabled = true
			snoozeWakeOnComment.integerValue = s.wakeOnComment ? 1 : 0
			snoozeWakeOnMention.isEnabled = true
			snoozeWakeOnMention.integerValue = s.wakeOnMention ? 1 : 0
			snoozeWakeOnStatusUpdate.isEnabled = true
			snoozeWakeOnStatusUpdate.integerValue = s.wakeOnStatusChange ? 1 : 0
			snoozeWakeLabel.textColor = NSColor.controlTextColor
			snoozeTypeDuration.isEnabled = true
			snoozeTypeDateTime.isEnabled = true
			snoozeDeletePreset.isEnabled = true
			snoozeUp.isEnabled = true
			snoozeDown.isEnabled = true
		} else {
			snoozeTypeDuration.isEnabled = false
			snoozeTypeDateTime.isEnabled = false
			snoozeDateTimeMinute.isEnabled = false
			snoozeDateTimeHour.isEnabled = false
			snoozeDateTimeDay.isEnabled = false
			snoozeDurationMinutes.isEnabled = false
			snoozeDurationHours.isEnabled = false
			snoozeDurationDays.isEnabled = false
			snoozeDeletePreset.isEnabled = false
			snoozeUp.isEnabled = false
			snoozeDown.isEnabled = false
			snoozeWakeOnComment.isEnabled = false
			snoozeWakeOnComment.integerValue = 0
			snoozeWakeOnMention.isEnabled = false
			snoozeWakeOnMention.integerValue = 0
			snoozeWakeOnStatusUpdate.isEnabled = false
			snoozeWakeOnStatusUpdate.integerValue = 0
			snoozeWakeLabel.textColor = NSColor.disabledControlTextColor
		}
	}

	private func commitSnoozeSettings() {
		snoozePresetsList.reloadData()
		deferredUpdateTimer.push()
		Settings.possibleExport(nil)
	}

	@IBAction func createNewSnoozePresetSelected(_ sender: NSButton) {
		let s = SnoozePreset.newSnoozePreset(in: mainObjectContext)
		commitSnoozeSettings()
		if let index = SnoozePreset.allSnoozePresets(in: mainObjectContext).index(of: s) {
			snoozePresetsList.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
			fillSnoozeFormFromSelectedPreset()
		}
	}

	@IBAction func deleteSnoozePresetSelected(_ sender: NSButton) {
		if let selectedPreset = selectedSnoozePreset(), let index = SnoozePreset.allSnoozePresets(in: mainObjectContext).index(of: selectedPreset) {

			let appliedCount = selectedPreset.appliedToIssues.count + selectedPreset.appliedToPullRequests.count
			if appliedCount > 0 {
				let alert = NSAlert()
				alert.messageText = "Warning"
				alert.informativeText = "You have \(appliedCount) items that have been snoozed using this preset. What would you like to do with them?"
				alert.addButton(withTitle: "Cancel")
				alert.addButton(withTitle: "Wake Them Up")
				alert.addButton(withTitle: "Keep Them Snoozed")
				alert.beginSheetModal(for: self) { [weak self] response in
					switch response {
					case 1000:
						break
					case 1001:
						selectedPreset.wakeUpAllAssociatedItems()
						fallthrough
					case 1002:
						self?.completeSnoozeDelete(selectedPreset, index)
					default: break
					}
				}
			} else {
				completeSnoozeDelete(selectedPreset, index)
			}
		}
	}

	private func completeSnoozeDelete(_ selectedPreset: SnoozePreset, _ index: Int) {
		mainObjectContext.delete(selectedPreset)
		commitSnoozeSettings()
		snoozePresetsList.selectRowIndexes(IndexSet(integer: min(index, snoozePresetsList.numberOfRows-1)), byExtendingSelection: false)
		fillSnoozeFormFromSelectedPreset()
	}

	@IBAction func snoozeTypeChanged(_ sender: NSButton) {
		if let s = selectedSnoozePreset() {
			s.duration = sender == snoozeTypeDuration
			fillSnoozeFormFromSelectedPreset()
			commitSnoozeSettings()
		}
	}

	@IBAction func snoozeOptionsChanged(_ sender: NSPopUpButton) {
		if let s = selectedSnoozePreset() {
			if s.duration {
				s.day = Int64(snoozeDurationDays.indexOfSelectedItem)
				s.hour = Int64(snoozeDurationHours.indexOfSelectedItem)
				s.minute = Int64(snoozeDurationMinutes.indexOfSelectedItem)
			} else {
				s.day = Int64(snoozeDateTimeDay.indexOfSelectedItem)
				s.hour = Int64(snoozeDateTimeHour.indexOfSelectedItem)
				s.minute = Int64(snoozeDateTimeMinute.indexOfSelectedItem)
			}
			commitSnoozeSettings()
		}
	}

	@IBAction func snoozeUpSelected(_ sender: AnyObject) {
		if let this = selectedSnoozePreset() {
			let all = SnoozePreset.allSnoozePresets(in: mainObjectContext)
			if let index = all.index(of: this), index > 0 {
				let other = all[index-1]
				other.sortOrder = Int64(index)
				this.sortOrder = Int64(index-1)
				snoozePresetsList.selectRowIndexes(IndexSet(integer: index-1), byExtendingSelection: false)
				commitSnoozeSettings()
			}
		}
	}

	@IBAction func snoozeDownSelected(_ sender: AnyObject) {
		if let this = selectedSnoozePreset() {
			let all = SnoozePreset.allSnoozePresets(in: mainObjectContext)
			if let index = all.index(of: this), index < all.count-1 {
				let other = all[index+1]
				other.sortOrder = Int64(index)
				this.sortOrder = Int64(index+1)
				snoozePresetsList.selectRowIndexes(IndexSet(integer: index+1), byExtendingSelection: false)
				commitSnoozeSettings()
			}
		}
	}
}
