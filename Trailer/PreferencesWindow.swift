
import Foundation

final class PreferencesWindow : NSWindow, NSWindowDelegate, NSTableViewDelegate, NSTableViewDataSource, NSTabViewDelegate {

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
	@IBOutlet weak var showCreationDates: NSButton!
	@IBOutlet weak var hideAvatars: NSButton!
	@IBOutlet weak var displayRepositoryNames: NSButton!
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
	@IBOutlet weak var autoParticipateOnTeamMentions: NSButton!
	@IBOutlet weak var autoParticipateWhenMentioned: NSButton!

	// Display
	@IBOutlet weak var useVibrancy: NSButton!
	@IBOutlet weak var includeLabelsInFiltering: NSButton!
	@IBOutlet weak var includeTitlesInFiltering: NSButton!
	@IBOutlet weak var includeStatusesInFiltering: NSButton!
	@IBOutlet weak var grayOutWhenRefreshing: NSButton!
	@IBOutlet weak var assignedPrHandlingPolicy: NSPopUpButton!
    @IBOutlet weak var includeServersInFiltering: NSButton!
    @IBOutlet weak var includeUsersInFiltering: NSButton!
	@IBOutlet weak var includeNumbersInFiltering: NSButton!
	@IBOutlet weak var refreshReposLabel: NSTextField!
	@IBOutlet weak var refreshItemsLabel: NSTextField!

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

	override init(contentRect: NSRect, styleMask aStyle: Int, backing bufferingType: NSBackingStoreType, `defer` flag: Bool) {
		super.init(contentRect: contentRect, styleMask: aStyle, backing: bufferingType, defer: flag)
	}

	override func awakeFromNib() {
		super.awakeFromNib()
		delegate = self

		updateAllItemSettingButtons()
		fillSnoozingDropdowns()

		allNewPrsSetting.addItemsWithTitles(RepoDisplayPolicy.labels)
		allNewIssuesSetting.addItemsWithTitles(RepoDisplayPolicy.labels)

		addTooltips()
		reloadSettings()

		versionNumber.stringValue = versionString()

		let selectedIndex = min(tabs.numberOfTabViewItems-1, Settings.lastPreferencesTabSelectedOSX)
		tabs.selectTabViewItem(tabs.tabViewItemAtIndex(selectedIndex))

		let n = NSNotificationCenter.defaultCenter()
		n.addObserver(serverList, selector: #selector(NSTableView.reloadData), name: API_USAGE_UPDATE, object: nil)
		n.addObserver(self, selector: #selector(PreferencesWindow.updateImportExportSettings), name: SETTINGS_EXPORTED, object: nil)
	}

	deinit {
		NSNotificationCenter.defaultCenter().removeObserver(serverList)
		NSNotificationCenter.defaultCenter().removeObserver(self)
	}

	private func addTooltips() {
		snoozePresetsList.toolTip = "The list of presets that will be displayed in the snooze context menu"
		serverList.toolTip = "The list of GitHub API servers that Trailer will attempt to sync data from. You can edit each server's details from the pane on the right. Bear in mind that some servers, like the public GitHub server for instance, have strict API volume limits, and syncing too many repos or items too often can result in API usage going over the limit. You can monitor your usage fro the bar next tot he server's name. If it is red, you're close to maximum. Your API usage is reset every hour."
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
		sortModeSelect.toolTip = Settings.sortMethodHelp
		sortingOrder.toolTip = Settings.sortDescendingHelp
		groupByRepo.toolTip = Settings.groupByRepoHelp
		assignedPrHandlingPolicy.toolTip = Settings.assignedPrHandlingPolicyHelp
		includeTitlesInFiltering.toolTip = Settings.includeTitlesInFilterHelp
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
		autoParticipateWhenMentioned.toolTip = Settings.autoParticipateInMentionsHelp
		autoParticipateOnTeamMentions.toolTip = Settings.autoParticipateOnTeamMentionsHelp
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
	}

	private func updateAllItemSettingButtons() {

		allPrsSetting.removeAllItems()
		allIssuesSetting.removeAllItems()
		allHidingSetting.removeAllItems()

		if projectsTable.selectedRowIndexes.count > 1 {
			allPrsSetting.addItemWithTitle("Set selected PRs...")
			allIssuesSetting.addItemWithTitle("Set selected issues...")
			allHidingSetting.addItemWithTitle("Set selected hiding...")
		} else if !repoFilter.stringValue.isEmpty {
			allPrsSetting.addItemWithTitle("Set filtered PRs...")
			allIssuesSetting.addItemWithTitle("Set filtered issues...")
			allHidingSetting.addItemWithTitle("Set filtered hiding...")
		} else {
			allPrsSetting.addItemWithTitle("Set all PRs...")
			allIssuesSetting.addItemWithTitle("Set all issues...")
			allHidingSetting.addItemWithTitle("Set all hiding...")
		}

		allPrsSetting.addItemsWithTitles(RepoDisplayPolicy.labels)
		allIssuesSetting.addItemsWithTitles(RepoDisplayPolicy.labels)
		allHidingSetting.addItemsWithTitles(RepoHidingPolicy.labels)
	}

	func reloadSettings() {
		let firstRow = NSIndexSet(index: 0)
		serverList.selectRowIndexes(firstRow, byExtendingSelection: false)
		fillServerApiFormFromSelectedServer()
		fillSnoozeFormFromSelectedPreset()

		api.updateLimitsFromServer()
		updateStatusTermPreferenceControls()
		commentAuthorBlacklist.objectValue = Settings.commentAuthorBlacklist

		setupSortMethodMenu()
		sortModeSelect.selectItemAtIndex(Settings.sortMethod)

		prMergedPolicy.selectItemAtIndex(Settings.mergeHandlingPolicy)
		prClosedPolicy.selectItemAtIndex(Settings.closeHandlingPolicy)

		launchAtStartup.integerValue = StartupLaunch.isAppLoginItem() ? 1 : 0
		dontConfirmRemoveAllClosed.integerValue = Settings.dontAskBeforeWipingClosed ? 1 : 0
		displayRepositoryNames.integerValue = Settings.showReposInName ? 1 : 0
		includeRepositoriesInFiltering.integerValue = Settings.includeReposInFilter ? 1 : 0
		includeLabelsInFiltering.integerValue = Settings.includeLabelsInFilter ? 1 : 0
		includeTitlesInFiltering.integerValue = Settings.includeTitlesInFilter ? 1 : 0
        includeUsersInFiltering.integerValue = Settings.includeUsersInFilter ? 1 : 0
		includeNumbersInFiltering.integerValue = Settings.includeNumbersInFilter ? 1 : 0
		includeServersInFiltering.integerValue = Settings.includeServersInFilter ? 1 : 0
		includeStatusesInFiltering.integerValue = Settings.includeStatusesInFilter ? 1 : 0
		dontConfirmRemoveAllMerged.integerValue = Settings.dontAskBeforeWipingMerged ? 1 : 0
		hideUncommentedPrs.integerValue = Settings.hideUncommentedItems ? 1 : 0
		autoParticipateWhenMentioned.integerValue = Settings.autoParticipateInMentions ? 1 : 0
		autoParticipateOnTeamMentions.integerValue = Settings.autoParticipateOnTeamMentions ? 1 : 0
		hideAvatars.integerValue = Settings.hideAvatars ? 1 : 0
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
		assignedPrHandlingPolicy.selectItemAtIndex(Settings.assignedPrHandlingPolicy)
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

		snoozeWakeOnComment.integerValue = Settings.snoozeWakeOnComment ? 1 : 0
		snoozeWakeOnMention.integerValue = Settings.snoozeWakeOnMention ? 1 : 0
		snoozeWakeOnStatusUpdate.integerValue = Settings.snoozeWakeOnStatusUpdate ? 1 : 0
		hideSnoozedItems.integerValue = Settings.hideSnoozedItems ? 1 : 0

		allNewPrsSetting.selectItemAtIndex(Settings.displayPolicyForNewPrs)
		allNewIssuesSetting.selectItemAtIndex(Settings.displayPolicyForNewIssues)

		hotkeyEnable.integerValue = Settings.hotkeyEnable ? 1 : 0
		hotkeyControlModifier.integerValue = Settings.hotkeyControlModifier ? 1 : 0
		hotkeyCommandModifier.integerValue = Settings.hotkeyCommandModifier ? 1 : 0
		hotkeyOptionModifier.integerValue = Settings.hotkeyOptionModifier ? 1 : 0
		hotkeyShiftModifier.integerValue = Settings.hotkeyShiftModifier ? 1 : 0

		enableHotkeySegments()

		hotkeyLetter.addItemsWithTitles(["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"])
		hotkeyLetter.selectItemWithTitle(Settings.hotkeyLetter)

		refreshUpdatePreferences()
		updateStatusItemsOptions()
		updateLabelOptions()
		updateHistoryOptions()

		hotkeyEnable.enabled = true

		repoCheckStepper.floatValue = Settings.newRepoCheckPeriod
		newRepoCheckChanged(nil)

		refreshDurationStepper.floatValue = min(Settings.refreshPeriod, 3600)
		refreshDurationChanged(nil)

		updateImportExportSettings()

		updateActivity()
	}

	func updateActivity() {
		if app.isRefreshing {
			refreshButton.enabled = false
			projectsTable.enabled = false
			allPrsSetting.enabled = false
			allIssuesSetting.enabled = false
			activityDisplay.startAnimation(nil)
		} else {
			refreshButton.enabled = ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext)
			projectsTable.enabled = true
			allPrsSetting.enabled = true
			allIssuesSetting.enabled = true
			activityDisplay.stopAnimation(nil)
		}
	}

	required init?(coder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}

	@IBAction func showLabelsSelected(sender: NSButton) {
		Settings.showLabels = (sender.integerValue==1)
		app.deferredUpdateTimer.push()
		updateLabelOptions()

		api.resetAllLabelChecks()
		if Settings.showLabels {
			ApiServer.resetSyncOfEverything()
		}
	}

	@IBAction func dontConfirmRemoveAllMergedSelected(sender: NSButton) {
		Settings.dontAskBeforeWipingMerged = (sender.integerValue==1)
	}

	@IBAction func markUnmergeableOnUserSectionsOnlySelected(sender: NSButton) {
		Settings.markUnmergeableOnUserSectionsOnly = (sender.integerValue==1)
		app.deferredUpdateTimer.push()
	}

	@IBAction func displayRepositoryNameSelected(sender: NSButton) {
		Settings.showReposInName = (sender.integerValue==1)
		app.deferredUpdateTimer.push()
	}

	@IBAction func useVibrancySelected(sender: NSButton) {
		Settings.useVibrancy = (sender.integerValue==1)
		app.prMenu.updateVibrancy()
		app.issuesMenu.updateVibrancy()
	}

	@IBAction func logActivityToConsoleSelected(sender: NSButton) {
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
			alert.addButtonWithTitle("OK")
			alert.beginSheetModalForWindow(self, completionHandler: nil)
		}
	}

	@IBAction func dumpApiResponsesToConsoleSelected(sender: NSButton) {
		Settings.dumpAPIResponsesInConsole = (sender.integerValue==1)
		if Settings.dumpAPIResponsesInConsole {
			let alert = NSAlert()
			alert.messageText = "Warning"
			alert.informativeText = "This is a feature meant for error reporting, having it constantly enabled will cause this app to be less responsive, use more power, and constitute a security risk"
			alert.addButtonWithTitle("OK")
			alert.beginSheetModalForWindow(self, completionHandler: nil)
		}
	}

    @IBAction func includeServersInFilteringSelected(sender: NSButton) {
        Settings.includeServersInFilter = (sender.integerValue==1)
		app.deferredUpdateTimer.push()
    }

	@IBAction func includeNumbersInFilteringSelected(sender: NSButton) {
		Settings.includeNumbersInFilter = (sender.integerValue==1)
		app.deferredUpdateTimer.push()
	}

    @IBAction func includeUsersInFilteringSelected(sender: NSButton) {
        Settings.includeUsersInFilter = (sender.integerValue==1)
		app.deferredUpdateTimer.push()
    }

	@IBAction func includeLabelsInFilteringSelected(sender: NSButton) {
		Settings.includeLabelsInFilter = (sender.integerValue==1)
		app.deferredUpdateTimer.push()
	}

	@IBAction func includeStatusesInFilteringSelected(sender: NSButton) {
		Settings.includeStatusesInFilter = (sender.integerValue==1)
		app.deferredUpdateTimer.push()
	}

	@IBAction func includeTitlesInFilteringSelected(sender: NSButton) {
		Settings.includeTitlesInFilter = (sender.integerValue==1)
		app.deferredUpdateTimer.push()
	}

	@IBAction func includeRepositoriesInfilterSelected(sender: NSButton) {
		Settings.includeReposInFilter = (sender.integerValue==1)
		app.deferredUpdateTimer.push()
	}

	@IBAction func dontConfirmRemoveAllClosedSelected(sender: NSButton) {
		Settings.dontAskBeforeWipingClosed = (sender.integerValue==1)
	}

	@IBAction func autoParticipateOnMentionSelected(sender: NSButton) {
		Settings.autoParticipateInMentions = (sender.integerValue==1)
		DataManager.postProcessAllItems()
		app.deferredUpdateTimer.push()
	}

	@IBAction func autoParticipateOnTeamMentionSelected(sender: NSButton) {
		Settings.autoParticipateOnTeamMentions = (sender.integerValue==1)
		DataManager.postProcessAllItems()
		app.deferredUpdateTimer.push()
	}

	@IBAction func removeNotificationsWhenItemIsRemovedSelected(sender: NSButton) {
		Settings.removeNotificationsWhenItemIsRemoved = (sender.integerValue==1)
	}

	@IBAction func dontKeepMyPrsSelected(sender: NSButton) {
		Settings.dontKeepPrsMergedByMe = (sender.integerValue==1)
		updateHistoryOptions()
	}

	private func updateHistoryOptions() {
		dontKeepPrsMergedByMe.enabled = Settings.mergeHandlingPolicy != PRHandlingPolicy.KeepNone.rawValue;
	}

	@IBAction func grayOutWhenRefreshingSelected(sender: NSButton) {
		Settings.grayOutWhenRefreshing = (sender.integerValue==1)
	}

	@IBAction func disableAllCommentNotificationsSelected(sender: NSButton) {
		Settings.disableAllCommentNotifications = (sender.integerValue==1)
	}

	@IBAction func notifyOnStatusUpdatesSelected(sender: NSButton) {
		Settings.notifyOnStatusUpdates = (sender.integerValue==1)
		updateStatusItemsOptions()
	}

	@IBAction func notifyOnStatusUpdatesOnAllPrsSelected(sender: NSButton) {
		Settings.notifyOnStatusUpdatesForAllPrs = (sender.integerValue==1)
	}

	@IBAction func hidePrsThatDontPassOnlyInAllSelected(sender: NSButton) {
		Settings.hidePrsThatDontPassOnlyInAll = (sender.integerValue==1)
		DataManager.postProcessAllItems()
		app.deferredUpdateTimer.push()
	}

	@IBAction func hidePrsThatDontPassSelected(sender: NSButton) {
		Settings.hidePrsThatArentPassing = (sender.integerValue==1)
		updateStatusItemsOptions()
		DataManager.postProcessAllItems()
		app.deferredUpdateTimer.push()
	}

	@IBAction func hideAvatarsSelected(sender: NSButton) {
		Settings.hideAvatars = (sender.integerValue==1)
		DataManager.postProcessAllItems()
		app.deferredUpdateTimer.push()
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

	@IBAction func allPrsPolicySelected(sender: NSPopUpButton) {
		let index = sender.indexOfSelectedItem - 1
		if index < 0 { return }

		for r in affectedReposFromSelection() {
			r.displayPolicyForPrs = index
			if index != RepoDisplayPolicy.Hide.rawValue { r.resetSyncState() }
		}
		projectsTable.reloadData()
		sender.selectItemAtIndex(0)
		updateDisplayIssuesSetting()
	}

	@IBAction func allIssuesPolicySelected(sender: NSPopUpButton) {
		let index = sender.indexOfSelectedItem - 1
		if index < 0 { return }

		for r in affectedReposFromSelection() {
			r.displayPolicyForIssues = index
			if index != RepoDisplayPolicy.Hide.rawValue { r.resetSyncState() }
		}
		projectsTable.reloadData()
		sender.selectItemAtIndex(0)
		updateDisplayIssuesSetting()
	}

	@IBAction func allHidingPolicySelected(sender: NSPopUpButton) {
		let index = sender.indexOfSelectedItem - 1
		if index < 0 { return }

		for r in affectedReposFromSelection() {
			r.itemHidingPolicy = index
		}
		projectsTable.reloadData()
		sender.selectItemAtIndex(0)
		updateDisplayIssuesSetting()
	}

	private func updateDisplayIssuesSetting() {
		DataManager.postProcessAllItems()
		app.preferencesDirty = true
		app.deferredUpdateTimer.push()
		DataManager.saveDB()
		Settings.possibleExport(nil)
	}

	@IBAction func allNewPrsPolicySelected(sender: NSPopUpButton) {
		Settings.displayPolicyForNewPrs = sender.indexOfSelectedItem
	}

	@IBAction func allNewIssuesPolicySelected(sender: NSPopUpButton) {
		Settings.displayPolicyForNewIssues = sender.indexOfSelectedItem
	}

	@IBAction func hideUncommentedRequestsSelected(sender: NSButton) {
		Settings.hideUncommentedItems = (sender.integerValue==1)
		DataManager.postProcessAllItems()
		app.deferredUpdateTimer.push()
	}

	@IBAction func showAllCommentsSelected(sender: NSButton) {
		Settings.showCommentsEverywhere = (sender.integerValue==1)
		DataManager.postProcessAllItems()
		app.deferredUpdateTimer.push()
	}

	@IBAction func sortOrderSelected(sender: NSButton) {
		Settings.sortDescending = (sender.integerValue==1)
		setupSortMethodMenu()
		DataManager.postProcessAllItems()
		app.deferredUpdateTimer.push()
	}

	@IBAction func countOnlyListedItemsSelected(sender: NSButton) {
		Settings.countOnlyListedItems = (sender.integerValue==0)
		DataManager.postProcessAllItems()
		app.deferredUpdateTimer.push()
	}

	@IBAction func openPrAtFirstUnreadCommentSelected(sender: NSButton) {
		Settings.openPrAtFirstUnreadComment = (sender.integerValue==1)
	}

	@IBAction func sortMethodChanged(sender: AnyObject) {
		Settings.sortMethod = sortModeSelect.indexOfSelectedItem
		DataManager.postProcessAllItems()
		app.deferredUpdateTimer.push()
	}

	@IBAction func showStatusItemsSelected(sender: NSButton) {
		Settings.showStatusItems = (sender.integerValue==1)
		app.deferredUpdateTimer.push()
		updateStatusItemsOptions()

		api.resetAllStatusChecks()
		if Settings.showStatusItems {
			ApiServer.resetSyncOfEverything()
		}
	}

	private func setupSortMethodMenu() {
		let m = NSMenu(title: "Sorting")
		if Settings.sortDescending {
			m.addItemWithTitle("Youngest First", action: #selector(PreferencesWindow.sortMethodChanged(_:)), keyEquivalent: "")
			m.addItemWithTitle("Most Recently Active", action: #selector(PreferencesWindow.sortMethodChanged(_:)), keyEquivalent: "")
			m.addItemWithTitle("Reverse Alphabetically", action: #selector(PreferencesWindow.sortMethodChanged(_:)), keyEquivalent: "")
		} else {
			m.addItemWithTitle("Oldest First", action: #selector(PreferencesWindow.sortMethodChanged(_:)), keyEquivalent: "")
			m.addItemWithTitle("Inactive For Longest", action: #selector(PreferencesWindow.sortMethodChanged(_:)), keyEquivalent: "")
			m.addItemWithTitle("Alphabetically", action: #selector(PreferencesWindow.sortMethodChanged(_:)), keyEquivalent: "")
		}
		sortModeSelect.menu = m
		sortModeSelect.selectItemAtIndex(Settings.sortMethod)
	}

	private func updateStatusItemsOptions() {
		let enable = Settings.showStatusItems
		makeStatusItemsSelectable.enabled = enable
		notifyOnStatusUpdates.enabled = enable
		notifyOnStatusUpdatesForAllPrs.enabled = enable
		statusTermMenu.enabled = enable
		statusItemRefreshCounter.enabled = enable
		statusItemRescanLabel.alphaValue = enable ? 1.0 : 0.5
		statusItemsRefreshNote.alphaValue = enable ? 1.0 : 0.5
		hidePrsThatDontPass.alphaValue = enable ? 1.0 : 0.5
		hidePrsThatDontPass.enabled = enable
		hidePrsThatDontPassOnlyInAll.enabled = enable && Settings.hidePrsThatArentPassing
		notifyOnStatusUpdatesForAllPrs.enabled = enable && Settings.notifyOnStatusUpdates

		let count = Settings.statusItemRefreshInterval
		statusItemRefreshCounter.integerValue = count
		statusItemRescanLabel.stringValue = count>1 ? "...and re-scan once every \(count) refreshes" : "...and re-scan on every refresh"

		updateStatusTermPreferenceControls()
	}

	private func updateLabelOptions() {
		let enable = Settings.showLabels
		labelRefreshCounter.enabled = enable
		labelRescanLabel.alphaValue = enable ? 1.0 : 0.5
		labelRefreshNote.alphaValue = enable ? 1.0 : 0.5

		let count = Settings.labelRefreshInterval
		labelRefreshCounter.integerValue = count
		labelRescanLabel.stringValue = count>1 ? "...and re-scan once every \(count) refreshes" : "...and re-scan on every refresh"
	}

	@IBAction func labelRefreshCounterChanged(sender: NSStepper) {
		Settings.labelRefreshInterval = labelRefreshCounter.integerValue
		updateLabelOptions()
	}

	@IBAction func statusItemRefreshCountChanged(sender: NSStepper) {
		Settings.statusItemRefreshInterval = statusItemRefreshCounter.integerValue
		updateStatusItemsOptions()
	}

	@IBAction func makeStatusItemsSelectableSelected(sender: NSButton) {
		Settings.makeStatusItemsSelectable = (sender.integerValue==1)
		app.deferredUpdateTimer.push()
	}

	@IBAction func showCreationSelected(sender: NSButton) {
		Settings.showCreatedInsteadOfUpdated = (sender.integerValue==1)
		DataManager.postProcessAllItems()
		app.deferredUpdateTimer.push()
	}

	@IBAction func groupbyRepoSelected(sender: NSButton) {
		Settings.groupByRepo = (sender.integerValue==1)
		app.deferredUpdateTimer.push()
	}

	@IBAction func assignedPrHandlingPolicySelected(sender: NSPopUpButton) {
		Settings.assignedPrHandlingPolicy = sender.indexOfSelectedItem;
		DataManager.postProcessAllItems()
		app.deferredUpdateTimer.push()
	}

	@IBAction func checkForUpdatesAutomaticallySelected(sender: NSButton) {
		Settings.checkForUpdatesAutomatically = (sender.integerValue==1)
		refreshUpdatePreferences()
	}

	private func refreshUpdatePreferences() {
		let setting = Settings.checkForUpdatesAutomatically
		let interval = Settings.checkForUpdatesInterval

		checkForUpdatesLabel.hidden = !setting
		checkForUpdatesSelector.hidden = !setting

		checkForUpdatesSelector.integerValue = interval
		checkForUpdatesAutomatically.integerValue = setting ? 1 : 0
		checkForUpdatesLabel.stringValue = interval<2 ? "Check every hour" : "Check every \(interval) hours"
	}

	@IBAction func checkForUpdatesIntervalChanged(sender: NSStepper) {
		Settings.checkForUpdatesInterval = sender.integerValue
		refreshUpdatePreferences()
	}

	@IBAction func launchAtStartSelected(sender: NSButton) {
		StartupLaunch.setLaunchOnLogin(sender.integerValue==1)
	}

	@IBAction func refreshReposSelected(sender: NSButton?) {
		app.prepareForRefresh()

		let tempContext = DataManager.tempContext()
		api.fetchRepositoriesToMoc(tempContext) {

			if ApiServer.shouldReportRefreshFailureInMoc(tempContext) {
				var errorServers = [String]()
				for apiServer in ApiServer.allApiServersInMoc(tempContext) {
					if apiServer.goodToGo && !apiServer.syncIsGood {
						errorServers.append(apiServer.label ?? "NoServerName")
					}
				}

				let serverNames = errorServers.joinWithSeparator(", ")

				let alert = NSAlert()
				alert.messageText = "Error"
				alert.informativeText = "Could not refresh repository list from \(serverNames), please ensure that the tokens you are using are valid"
				alert.addButtonWithTitle("OK")
				alert.runModal()
			} else {
				do {
					try tempContext.save()
				} catch _ {
				}
			}
			app.completeRefresh()
		}
	}

	private func selectedServer() -> ApiServer? {
		let selected = serverList.selectedRow
		if selected >= 0 {
			return ApiServer.allApiServersInMoc(mainObjectContext)[selected]
		}
		return nil
	}

	@IBAction func deleteSelectedServerSelected(sender: NSButton) {
		if let selectedServer = selectedServer(), index = ApiServer.allApiServersInMoc(mainObjectContext).indexOf(selectedServer) {
			mainObjectContext.deleteObject(selectedServer)
			serverList.reloadData()
			serverList.selectRowIndexes(NSIndexSet(index: min(index, serverList.numberOfRows-1)), byExtendingSelection: false)
			fillServerApiFormFromSelectedServer()
			app.deferredUpdateTimer.push()
			DataManager.saveDB()
		}
	}

	@IBAction func apiServerReportErrorSelected(sender: NSButton) {
		if let apiServer = selectedServer() {
			apiServer.reportRefreshFailures = (sender.integerValue != 0)
			storeApiFormToSelectedServer()
		}
	}

	func updateImportExportSettings() {
		repeatLastExportAutomatically.integerValue = Settings.autoRepeatSettingsExport ? 1 : 0
		if let lastExportDate = Settings.lastExportDate, fileName = Settings.lastExportUrl?.absoluteString, unescapedName = fileName.stringByRemovingPercentEncoding {
			let time = itemDateFormatter.stringFromDate(lastExportDate)
			lastExportReport.stringValue = "Last exported \(time) to \(unescapedName)"
		} else {
			lastExportReport.stringValue = ""
		}
	}

	@IBAction func repeatLastExportSelected(sender: AnyObject) {
		Settings.autoRepeatSettingsExport = (repeatLastExportAutomatically.integerValue==1)
	}

	@IBAction func exportCurrentSettingsSelected(sender: NSButton) {
		let s = NSSavePanel()
		s.title = "Export Current Settings..."
		s.prompt = "Export"
		s.nameFieldLabel = "Settings File"
		s.message = "Export Current Settings..."
		s.extensionHidden = false
		s.nameFieldStringValue = "Trailer Settings"
		s.allowedFileTypes = ["trailerSettings"]
		s.beginSheetModalForWindow(self) { response in
			if response == NSFileHandlingPanelOKButton, let url = s.URL {
				Settings.writeToURL(url)
				DLog("Exported settings to %@", url.absoluteString)
			}
		}
	}

	@IBAction func importSettingsSelected(sender: NSButton) {
		let o = NSOpenPanel()
		o.title = "Import Settings From File..."
		o.prompt = "Import"
		o.nameFieldLabel = "Settings File"
		o.message = "Import Settings From File..."
		o.extensionHidden = false
		o.allowedFileTypes = ["trailerSettings"]
		o.beginSheetModalForWindow(self) { response in
			if response == NSFileHandlingPanelOKButton, let url = o.URL {
				atNextEvent {
					app.tryLoadSettings(url, skipConfirm: Settings.dontConfirmSettingsImport)
				}
			}
		}
	}

	private func colorButton(button: NSButton, withColor: NSColor) {
		let title = button.attributedTitle.mutableCopy() as! NSMutableAttributedString
		title.addAttribute(NSForegroundColorAttributeName, value: withColor, range: NSMakeRange(0, title.length))
		button.attributedTitle = title
	}

	private func enableHotkeySegments() {
		if Settings.hotkeyEnable {
			colorButton(hotkeyCommandModifier, withColor: Settings.hotkeyCommandModifier ? NSColor.controlTextColor() : NSColor.disabledControlTextColor())
			colorButton(hotkeyControlModifier, withColor: Settings.hotkeyControlModifier ? NSColor.controlTextColor() : NSColor.disabledControlTextColor())
			colorButton(hotkeyOptionModifier, withColor: Settings.hotkeyOptionModifier ? NSColor.controlTextColor() : NSColor.disabledControlTextColor())
			colorButton(hotkeyShiftModifier, withColor: Settings.hotkeyShiftModifier ? NSColor.controlTextColor() : NSColor.disabledControlTextColor())
		}
		hotKeyContainer.hidden = !Settings.hotkeyEnable
		hotKeyHelp.hidden = Settings.hotkeyEnable
	}

	@IBAction func enableHotkeySelected(sender: AnyObject) {
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
		alert.addButtonWithTitle("OK")
		alert.runModal()
	}

	@IBAction func createTokenSelected(sender: NSButton) {
		if apiServerWebPath.stringValue.isEmpty {
			reportNeedFrontEnd()
		} else {
			let address = apiServerWebPath.stringValue + "/settings/tokens/new"
			NSWorkspace.sharedWorkspace().openURL(NSURL(string: address)!)
		}
	}

	@IBAction func viewExistingTokensSelected(sender: NSButton) {
		if apiServerWebPath.stringValue.isEmpty {
			reportNeedFrontEnd()
		} else {
			let address = apiServerWebPath.stringValue + "/settings/applications"
			NSWorkspace.sharedWorkspace().openURL(NSURL(string: address)!)
		}
	}

	@IBAction func viewWatchlistSelected(sender: NSButton) {
		if apiServerWebPath.stringValue.isEmpty {
			reportNeedFrontEnd()
		} else {
			let address = apiServerWebPath.stringValue + "/watching"
			NSWorkspace.sharedWorkspace().openURL(NSURL(string: address)!)
		}
	}

	@IBAction func prMergePolicySelected(sender: NSPopUpButton) {
		Settings.mergeHandlingPolicy = sender.indexOfSelectedItem
		updateHistoryOptions()
	}

	@IBAction func prClosePolicySelected(sender: NSPopUpButton) {
		Settings.closeHandlingPolicy = sender.indexOfSelectedItem
	}

	private func updateStatusTermPreferenceControls() {
		let mode = Settings.statusFilteringMode
		statusTermMenu.selectItemAtIndex(mode)
		if mode != 0 {
			statusTermsField.enabled = true
			statusTermsField.alphaValue = 1.0
		}
		else
		{
			statusTermsField.enabled = false
			statusTermsField.alphaValue = 0.5
		}
		statusTermsField.objectValue = Settings.statusFilteringTerms
	}

	@IBAction func statusFilterMenuChanged(sender: NSPopUpButton) {
		Settings.statusFilteringMode = sender.indexOfSelectedItem
		Settings.statusFilteringTerms = statusTermsField.objectValue as! [String]
		updateStatusTermPreferenceControls()
		app.deferredUpdateTimer.push()
	}

	@IBAction func testApiServerSelected(sender: NSButton) {
		sender.enabled = false
		let apiServer = selectedServer()!
		api.testApiToServer(apiServer) { error in
			let alert = NSAlert()
			if error != nil {
				alert.messageText = "The test failed for " + (apiServer.apiPath ?? "NoApiPath")
				alert.informativeText = error!.localizedDescription
			} else {
				alert.messageText = "This API server seems OK!"
			}
			alert.addButtonWithTitle("OK")
			alert.runModal()
			sender.enabled = true
		}
	}

	@IBAction func apiRestoreDefaultsSelected(sender: NSButton)
	{
		if let apiServer = selectedServer() {
			apiServer.resetToGithub()
			fillServerApiFormFromSelectedServer()
			storeApiFormToSelectedServer()
		}
	}

	private func fillServerApiFormFromSelectedServer() {
		if let apiServer = selectedServer() {
			apiServerName.stringValue = apiServer.label ?? ""
			apiServerWebPath.stringValue = apiServer.webPath ?? ""
			apiServerApiPath.stringValue = apiServer.apiPath ?? ""
			apiServerAuthToken.stringValue = apiServer.authToken ?? ""
			apiServerSelectedBox.title = apiServer.label ?? "New Server"
			apiServerTestButton.enabled = !(apiServer.authToken ?? "").isEmpty
			apiServerDeleteButton.enabled = (ApiServer.countApiServersInMoc(mainObjectContext) > 1)
			apiServerReportError.integerValue = apiServer.reportRefreshFailures.boolValue ? 1 : 0
		}
	}

	private func storeApiFormToSelectedServer() {
		if let apiServer = selectedServer() {
			apiServer.label = apiServerName.stringValue
			apiServer.apiPath = apiServerApiPath.stringValue
			apiServer.webPath = apiServerWebPath.stringValue
			apiServer.authToken = apiServerAuthToken.stringValue
			apiServerTestButton.enabled = !(apiServer.authToken ?? "").isEmpty
			serverList.reloadData()
		}
	}

	@IBAction func addNewApiServerSelected(sender: NSButton) {
		let a = ApiServer.insertNewServerInMoc(mainObjectContext)
		a.label = "New API Server"
		serverList.reloadData()
		if let index = ApiServer.allApiServersInMoc(mainObjectContext).indexOf(a) {
			serverList.selectRowIndexes(NSIndexSet(index: index), byExtendingSelection: false)
			fillServerApiFormFromSelectedServer()
		}
	}

	@IBAction func refreshDurationChanged(sender: NSStepper?) {
		Settings.refreshPeriod = refreshDurationStepper.floatValue
		refreshDurationLabel.stringValue = "Refresh items every \(refreshDurationStepper.integerValue) seconds"
	}

	@IBAction func newRepoCheckChanged(sender: NSStepper?) {
		Settings.newRepoCheckPeriod = repoCheckStepper.floatValue
		repoCheckLabel.stringValue = "Refresh repos & teams every \(repoCheckStepper.integerValue) hours"
	}

	func windowWillClose(notification: NSNotification) {
		if ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext) && app.preferencesDirty {
			app.startRefresh()
		} else {
			if app.refreshTimer == nil && Settings.refreshPeriod > 0.0 {
				app.startRefreshIfItIsDue()
			}
		}
		app.setUpdateCheckParameters()
		app.closedPreferencesWindow()
	}

	override func controlTextDidChange(n: NSNotification?) {
		if let obj: AnyObject = n?.object {

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
					app.reset()
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
					app.reset()
				}
			} else if obj===repoFilter {
				projectsTable.reloadData()
				updateAllItemSettingButtons()
			} else if obj===statusTermsField {
				let existingTokens = Settings.statusFilteringTerms
				let newTokens = statusTermsField.objectValue as! [String]
				if existingTokens != newTokens {
					Settings.statusFilteringTerms = newTokens
					app.deferredUpdateTimer.push()
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

	func tabView(tabView: NSTabView, willSelectTabViewItem tabViewItem: NSTabViewItem?) {
		if let item = tabViewItem {
			let newIndex = tabView.indexOfTabViewItem(item)
			if newIndex == 1 {
				if (app.lastRepoCheck.isEqualToDate(never()) || Repo.countVisibleReposInMoc(mainObjectContext) == 0) && ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext) {
					refreshReposSelected(nil)
				}
			}
			Settings.lastPreferencesTabSelectedOSX = newIndex
		}
	}

	///////////// Repo table

	func tableViewSelectionDidChange(notification: NSNotification) {
		if serverList === notification.object {
			fillServerApiFormFromSelectedServer()
		} else if projectsTable === notification.object {
			updateAllItemSettingButtons()
		} else if snoozePresetsList === notification.object {
			fillSnoozeFormFromSelectedPreset()
		}
	}

	private func repoForRow(row: Int) -> Repo {
		let parentCount = Repo.countParentRepos(repoFilter.stringValue)
		var r = row
		if r > parentCount {
			r -= 1
		}
		let filteredRepos = Repo.reposForFilter(repoFilter.stringValue)
		return filteredRepos[r-1]
	}

	func tableView(tv: NSTableView, shouldSelectRow row: Int) -> Bool {
		return !tableView(tv, isGroupRow:row)
	}

	func tableView(tv: NSTableView, willDisplayCell c: AnyObject, forTableColumn tableColumn: NSTableColumn?, row: Int) {
		let cell = c as! NSCell
		if tv === projectsTable {
			if tableColumn?.identifier == "repos" {
				if tableView(tv, isGroupRow:row) {
					cell.title = row==0 ? "Parent Repositories" : "Forked Repositories"
					cell.enabled = false
				} else {
					cell.enabled = true
					let r = repoForRow(row)
					let repoName = r.fullName ?? "NoRepoName"
					let title = (r.inaccessible?.boolValue ?? false) ? repoName + " (inaccessible)" : repoName
					let textColor = (row == tv.selectedRow) ? NSColor.selectedControlTextColor() : (r.shouldSync() ? NSColor.textColor() : NSColor.textColor().colorWithAlphaComponent(0.4))
					cell.attributedStringValue = NSAttributedString(string: title, attributes: [NSForegroundColorAttributeName: textColor])
				}
			} else {
				if let menuCell = cell as? NSPopUpButtonCell {
					menuCell.removeAllItems()
					if tableView(tv, isGroupRow:row) {
						menuCell.selectItemAtIndex(-1)
						menuCell.enabled = false
						menuCell.arrowPosition = NSPopUpArrowPosition.NoArrow
					} else {
						let r = repoForRow(row)
						menuCell.enabled = true
						menuCell.arrowPosition = NSPopUpArrowPosition.ArrowAtBottom

						var count = 0
						let fontSize = NSFont.systemFontSizeForControlSize(NSControlSize.SmallControlSize)
						if tableColumn?.identifier == "hide" {
							for policy in RepoHidingPolicy.policies {
								let m = NSMenuItem()
								m.attributedTitle = NSAttributedString(string: policy.name(), attributes: [
									NSFontAttributeName: count==0 ? NSFont.systemFontOfSize(fontSize) : NSFont.boldSystemFontOfSize(fontSize),
									NSForegroundColorAttributeName: policy.color(),
									])
								menuCell.menu?.addItem(m)
								count += 1
							}
							menuCell.selectItemAtIndex(r.itemHidingPolicy?.integerValue ?? 0)
						} else {
							for policy in RepoDisplayPolicy.policies {
								let m = NSMenuItem()
								m.attributedTitle = NSAttributedString(string: policy.name(), attributes: [
									NSFontAttributeName: count==0 ? NSFont.systemFontOfSize(fontSize) : NSFont.boldSystemFontOfSize(fontSize),
									NSForegroundColorAttributeName: policy.color(),
									])
								menuCell.menu?.addItem(m)
								count += 1
							}
							let selectedIndex = tableColumn?.identifier == "prs" ? (r.displayPolicyForPrs?.integerValue ?? 0) : (r.displayPolicyForIssues?.integerValue ?? 0)
							menuCell.selectItemAtIndex(selectedIndex)
						}
					}
				}
			}
		} else if tv == serverList {
			let allServers = ApiServer.allApiServersInMoc(mainObjectContext)
			let apiServer = allServers[row]
			if tableColumn?.identifier == "server" {
				cell.title = apiServer.label ?? "NoApiServer"
				let tc = c as! NSTextFieldCell
				if apiServer.lastSyncSucceeded?.boolValue ?? false {
					tc.textColor = NSColor.textColor()
				} else {
					tc.textColor = NSColor.redColor()
				}
			} else { // api usage
				let c = cell as! NSLevelIndicatorCell
				c.minValue = 0
				let rl = apiServer.requestsLimit?.doubleValue ?? 0.0
				c.maxValue = rl
				c.warningValue = rl*0.5
				c.criticalValue = rl*0.8
				c.doubleValue = rl - (apiServer.requestsRemaining?.doubleValue ?? 0)
			}
		} else if tv == snoozePresetsList {
			let allPresets = SnoozePreset.allSnoozePresetsInMoc(mainObjectContext)
			let preset = allPresets[row]
			cell.title = preset.listDescription()
			let tc = c as! NSTextFieldCell
			tc.textColor = NSColor.textColor()
		}
	}

	func tableView(tableView: NSTableView, isGroupRow row: Int) -> Bool {
		if tableView === projectsTable {
			return (row == 0 || row == Repo.countParentRepos(repoFilter.stringValue) + 1)
		} else {
			return false
		}
	}

	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		if tableView === projectsTable {
			return Repo.reposForFilter(repoFilter.stringValue).count + 2
		} else if tableView === serverList {
			return ApiServer.countApiServersInMoc(mainObjectContext)
		} else if tableView === snoozePresetsList {
			return SnoozePreset.allSnoozePresetsInMoc(mainObjectContext).count
		}
		return 0
	}

	func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		return nil
	}

	func tableView(tv: NSTableView, setObjectValue object: AnyObject?, forTableColumn tableColumn: NSTableColumn?, row: Int) {
		if tv === projectsTable {
			if !tableView(tv, isGroupRow: row) {
				let r = repoForRow(row)
				if let index = object?.integerValue {
					if tableColumn?.identifier == "prs" {
						r.displayPolicyForPrs = index
					} else if tableColumn?.identifier == "issues" {
						r.displayPolicyForIssues = index
					} else if tableColumn?.identifier == "hide" {
						r.itemHidingPolicy = index
					}
					if index != RepoDisplayPolicy.Hide.rawValue {
						r.resetSyncState()
					}
					updateDisplayIssuesSetting()
				}
			}
		}
	}

	/////////////////////////////// snoozing

	@IBAction func snoozeWakeChanged(sender: NSButton) {
		Settings.snoozeWakeOnComment = snoozeWakeOnComment.integerValue == 1
		Settings.snoozeWakeOnMention = snoozeWakeOnMention.integerValue == 1
		Settings.snoozeWakeOnStatusUpdate = snoozeWakeOnStatusUpdate.integerValue == 1
		snoozePresetsList.reloadData()
		app.deferredUpdateTimer.push()
	}

	@IBAction func hideSnoozedItemsChanged(sender: NSButton) {
		Settings.hideSnoozedItems = hideSnoozedItems.integerValue == 1
		app.deferredUpdateTimer.push()
	}

	private func fillSnoozingDropdowns() {
		snoozeDurationDays.addItemWithTitle("")
		snoozeDurationHours.addItemWithTitle("")
		snoozeDurationMinutes.addItemWithTitle("")

		snoozeDurationDays.addItemWithTitle("1 day")
		snoozeDurationHours.addItemWithTitle("1 hour")
		snoozeDurationMinutes.addItemWithTitle("1 minute")

		var titles = [String]()

		for f in 2..<400 {
			titles.append("\(f) days")
		}
		snoozeDurationDays.addItemsWithTitles(titles)
		titles.removeAll()
		for f in 2..<24 {
			titles.append("\(f) hours")
		}
		snoozeDurationHours.addItemsWithTitles(titles)
		titles.removeAll()
		for f in 2..<60 {
			titles.append("\(f) minutes")
		}
		snoozeDurationMinutes.addItemsWithTitles(titles)
		titles.removeAll()

		snoozeDateTimeDay.addItemsWithTitles(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
		for f in 0..<24 {
			titles.append(String(format: "%02d", f))
		}
		snoozeDateTimeHour.addItemsWithTitles(titles)
		titles.removeAll()
		for f in 0..<60 {
			titles.append(String(format: "%02d", f))
		}
		snoozeDateTimeMinute.addItemsWithTitles(titles)
	}

	func selectedSnoozePreset() -> SnoozePreset? {
		let selected = snoozePresetsList.selectedRow
		if selected >= 0 {
			return SnoozePreset.allSnoozePresetsInMoc(mainObjectContext)[selected]
		}
		return nil
	}

	func fillSnoozeFormFromSelectedPreset() {
		if let s = selectedSnoozePreset() {
			if s.duration.boolValue {
				snoozeTypeDuration.integerValue = 1
				snoozeTypeDateTime.integerValue = 0
				snoozeDurationMinutes.enabled = true
				snoozeDurationHours.enabled = true
				snoozeDurationDays.enabled = true
				snoozeDurationMinutes.selectItemAtIndex(s.minute?.integerValue ?? 0)
				snoozeDurationHours.selectItemAtIndex(s.hour?.integerValue ?? 0)
				snoozeDurationDays.selectItemAtIndex(s.day?.integerValue ?? 0)
				snoozeDateTimeMinute.enabled = false
				snoozeDateTimeMinute.selectItemAtIndex(0)
				snoozeDateTimeHour.enabled = false
				snoozeDateTimeHour.selectItemAtIndex(0)
				snoozeDateTimeDay.enabled = false
				snoozeDateTimeDay.selectItemAtIndex(0)
			} else {
				snoozeTypeDuration.integerValue = 0
				snoozeTypeDateTime.integerValue = 1
				snoozeDurationMinutes.enabled = false
				snoozeDurationMinutes.selectItemAtIndex(0)
				snoozeDurationHours.enabled = false
				snoozeDurationHours.selectItemAtIndex(0)
				snoozeDurationDays.enabled = false
				snoozeDurationDays.selectItemAtIndex(0)
				snoozeDateTimeMinute.enabled = true
				snoozeDateTimeHour.enabled = true
				snoozeDateTimeDay.enabled = true
				snoozeDateTimeMinute.selectItemAtIndex(s.minute?.integerValue ?? 0)
				snoozeDateTimeHour.selectItemAtIndex(s.hour?.integerValue ?? 0)
				snoozeDateTimeDay.selectItemAtIndex(s.day?.integerValue ?? 0)
			}
			snoozeTypeDuration.enabled = true
			snoozeTypeDateTime.enabled = true
			snoozeDeletePreset.enabled = true
			snoozeUp.enabled = true
			snoozeDown.enabled = true
		} else {
			snoozeTypeDuration.enabled = false
			snoozeTypeDateTime.enabled = false
			snoozeDateTimeMinute.enabled = false
			snoozeDateTimeHour.enabled = false
			snoozeDateTimeDay.enabled = false
			snoozeDurationMinutes.enabled = false
			snoozeDurationHours.enabled = false
			snoozeDurationDays.enabled = false
			snoozeDeletePreset.enabled = false
			snoozeUp.enabled = false
			snoozeDown.enabled = false
		}
	}

	@IBAction func createNewSnoozePresetSelected(sender: NSButton) {
		let s = SnoozePreset.newSnoozePresetInMoc(mainObjectContext)
		snoozePresetsList.reloadData()
		if let index = SnoozePreset.allSnoozePresetsInMoc(mainObjectContext).indexOf(s) {
			snoozePresetsList.selectRowIndexes(NSIndexSet(index: index), byExtendingSelection: false)
			fillSnoozeFormFromSelectedPreset()
		}
		app.deferredUpdateTimer.push()
	}

	@IBAction func deleteSnoozePresetSelected(sender: NSButton) {
		if let selectedPreset = selectedSnoozePreset(), index = SnoozePreset.allSnoozePresetsInMoc(mainObjectContext).indexOf(selectedPreset) {
			mainObjectContext.deleteObject(selectedPreset)
			snoozePresetsList.reloadData()
			snoozePresetsList.selectRowIndexes(NSIndexSet(index: min(index, snoozePresetsList.numberOfRows-1)), byExtendingSelection: false)
			fillSnoozeFormFromSelectedPreset()
			DataManager.saveDB()
			app.deferredUpdateTimer.push()
		}
	}

	@IBAction func snoozeTypeChanged(sender: NSButton) {
		if let s = selectedSnoozePreset() {
			s.duration = NSNumber(bool: (sender == snoozeTypeDuration))
			fillSnoozeFormFromSelectedPreset()
			snoozePresetsList.reloadData()
			DataManager.saveDB()
			app.deferredUpdateTimer.push()
		}
	}

	@IBAction func snoozeOptionsChanged(sender: NSPopUpButton) {
		if let s = selectedSnoozePreset() {
			if s.duration.boolValue {
				s.day = numberOrNil(snoozeDurationDays.indexOfSelectedItem)
				s.hour = numberOrNil(snoozeDurationHours.indexOfSelectedItem)
				s.minute = numberOrNil(snoozeDurationMinutes.indexOfSelectedItem)
			} else {
				s.day = numberOrNil(snoozeDateTimeDay.indexOfSelectedItem)
				s.hour = numberOrNil(snoozeDateTimeHour.indexOfSelectedItem)
				s.minute = numberOrNil(snoozeDateTimeMinute.indexOfSelectedItem)
			}
			snoozePresetsList.reloadData()
			DataManager.saveDB()
			app.deferredUpdateTimer.push()
		}
	}

	@IBAction func snoozeUpSelected(sender: AnyObject) {
		if let this = selectedSnoozePreset() {
			let all = SnoozePreset.allSnoozePresetsInMoc(mainObjectContext)
			if let index = all.indexOf(this) where index > 0 {
				let other = all[index-1]
				other.sortOrder = NSNumber(integer: index)
				this.sortOrder = NSNumber(integer: index-1)
				snoozePresetsList.selectRowIndexes(NSIndexSet(index: index-1), byExtendingSelection: false)
				snoozePresetsList.reloadData()
				DataManager.saveDB()
				app.deferredUpdateTimer.push()
			}
		}
	}

	@IBAction func snoozeDownSelected(sender: AnyObject) {
		if let this = selectedSnoozePreset() {
			let all = SnoozePreset.allSnoozePresetsInMoc(mainObjectContext)
			if let index = all.indexOf(this) where index < all.count-1 {
				let other = all[index+1]
				other.sortOrder = NSNumber(integer: index)
				this.sortOrder = NSNumber(integer: index+1)
				snoozePresetsList.selectRowIndexes(NSIndexSet(index: index+1), byExtendingSelection: false)
				snoozePresetsList.reloadData()
				DataManager.saveDB()
				app.deferredUpdateTimer.push()
			}
		}
	}

	private func numberOrNil(i: Int) -> NSNumber? {
		return i > 0 ? NSNumber(integer: i) : nil
	}
}
