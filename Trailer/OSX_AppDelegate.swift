
var app: OSX_AppDelegate!

final class OSX_AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSUserNotificationCenterDelegate, NSTableViewDelegate, NSTableViewDataSource, NSTabViewDelegate, NSOpenSavePanelDelegate {

	// Preferences window
	@IBOutlet weak var preferencesWindow: NSWindow!
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
	@IBOutlet weak var dontKeepPrsMergedByMe: NSButton!
	@IBOutlet weak var hideAvatars: NSButton!
	@IBOutlet weak var dontConfirmRemoveAllMerged: NSButton!
	@IBOutlet weak var dontConfirmRemoveAllClosed: NSButton!
	@IBOutlet weak var displayRepositoryNames: NSButton!
	@IBOutlet weak var includeRepositoriesInFiltering: NSButton!
	@IBOutlet weak var groupByRepo: NSButton!
	@IBOutlet weak var hideAllPrsSection: NSButton!
	@IBOutlet weak var moveAssignedPrsToMySection: NSButton!
	@IBOutlet weak var markUnmergeableOnUserSectionsOnly: NSButton!
	@IBOutlet weak var repoCheckLabel: NSTextField!
	@IBOutlet weak var repoCheckStepper: NSStepper!
	@IBOutlet weak var countOnlyListedPrs: NSButton!
	@IBOutlet weak var prMergedPolicy: NSPopUpButton!
	@IBOutlet weak var prClosedPolicy: NSPopUpButton!
	@IBOutlet weak var checkForUpdatesAutomatically: NSButton!
	@IBOutlet weak var checkForUpdatesLabel: NSTextField!
	@IBOutlet weak var checkForUpdatesSelector: NSStepper!
	@IBOutlet weak var hideNewRepositories: NSButton!
	@IBOutlet weak var openPrAtFirstUnreadComment: NSButton!
	@IBOutlet weak var logActivityToConsole: NSButton!
	@IBOutlet weak var commentAuthorBlacklist: NSTokenField!

	// Preferences - Statuses
	@IBOutlet weak var showStatusItems: NSButton!
	@IBOutlet weak var makeStatusItemsSelectable: NSButton!
	@IBOutlet weak var statusItemRescanLabel: NSTextField!
	@IBOutlet weak var statusItemRefreshCounter: NSStepper!
	@IBOutlet weak var statusItemsRefreshNote: NSTextField!
	@IBOutlet weak var notifyOnStatusUpdates: NSButton!
	@IBOutlet weak var notifyOnStatusUpdatesForAllPrs: NSButton!
	@IBOutlet weak var statusTermMenu: NSPopUpButton!
	@IBOutlet weak var statusTermsField: NSTokenField!
	
    // Preferences - Comments
    @IBOutlet weak var disableAllCommentNotifications: NSButton!
	@IBOutlet weak var autoParticipateOnTeamMentions: NSButton!
	@IBOutlet weak var autoParticipateWhenMentioned: NSButton!

	// Preferences - Display
	@IBOutlet weak var useVibrancy: NSButton!
	@IBOutlet weak var includeLabelsInFiltering: NSButton!
	@IBOutlet weak var includeStatusesInFiltering: NSButton!
    @IBOutlet weak var grayOutWhenRefreshing: NSButton!
	@IBOutlet weak var showIssuesMenu: NSButton!

	// Preferences - Labels
	@IBOutlet weak var labelRescanLabel: NSTextField!
	@IBOutlet weak var labelRefreshNote: NSTextField!
	@IBOutlet weak var labelRefreshCounter: NSStepper!
	@IBOutlet weak var showLabels: NSButton!

	// Preferences - Servers
	@IBOutlet weak var serverList: NSTableView!
	@IBOutlet weak var apiServerName: NSTextField!
	@IBOutlet weak var apiServerApiPath: NSTextField!
	@IBOutlet weak var apiServerWebPath: NSTextField!
	@IBOutlet weak var apiServerAuthToken: NSTextField!
	@IBOutlet weak var apiServerSelectedBox: NSBox!
	@IBOutlet weak var apiServerTestButton: NSButton!
	@IBOutlet weak var apiServerDeleteButton: NSButton!
	@IBOutlet weak var apiServerReportError: NSButton!

	// Preferences - Misc
	@IBOutlet weak var repeatLastExportAutomatically: NSButton!
	@IBOutlet weak var lastExportReport: NSTextField!

	// Preferences - Keyboard
	@IBOutlet weak var hotkeyEnable: NSButton!
	@IBOutlet weak var hotkeyCommandModifier: NSButton!
	@IBOutlet weak var hotkeyOptionModifier: NSButton!
	@IBOutlet weak var hotkeyShiftModifier: NSButton!
	@IBOutlet weak var hotkeyLetter: NSPopUpButton!
	@IBOutlet weak var hotKeyHelp: NSTextField!
	@IBOutlet weak var hotKeyContainer: NSBox!
	@IBOutlet weak var hotkeyControlModifier: NSButton!

	// Menu
	static let prMenuController = NSWindowController(windowNibName:"MenuWindow")
	static let issuesMenuController = NSWindowController(windowNibName:"MenuWindow")
	let prMenu = prMenuController.window as! MenuWindow
	let issuesMenu = issuesMenuController.window as! MenuWindow

	// Globals
	weak var refreshTimer: NSTimer?
	var lastRepoCheck = never()
	var preferencesDirty: Bool = false
	var isRefreshing: Bool = false
	var isManuallyScrolling: Bool = false
	var ignoreNextFocusLoss: Bool = false
	var scrollBarWidth: CGFloat = 0.0
	var pullRequestDelegate = PullRequestDelegate()
	var issuesDelegate = IssuesDelegate()
	var opening: Bool  = false

	private var globalKeyMonitor: AnyObject?
	private var localKeyMonitor: AnyObject?
	private var mouseIgnoreTimer: PopTimer!
	private var prFilterTimer: PopTimer!
	private var issuesFilterTimer: PopTimer!
	private var deferredUpdateTimer: PopTimer!

	func applicationDidFinishLaunching(notification: NSNotification) {
		app = self

		setupDarkModeMonitoring()

		setupSortMethodMenu()
		DataManager.postProcessAllItems()

		prFilterTimer = PopTimer(timeInterval: 0.2) {
			app.updatePrMenu()
			app.prMenu.scrollToTop()
		}

		issuesFilterTimer = PopTimer(timeInterval: 0.2) {
			app.updateIssuesMenu()
			app.issuesMenu.scrollToTop()
		}

		deferredUpdateTimer = PopTimer(timeInterval: 0.5) {
			app.updatePrMenu()
			app.updateIssuesMenu()
		}

		mouseIgnoreTimer = PopTimer(timeInterval: 0.4) {
			app.isManuallyScrolling = false
		}

		prMenu.table.setDataSource(pullRequestDelegate)
		prMenu.table.setDelegate(pullRequestDelegate)
		prMenu.delegate = self

		issuesMenu.table.setDataSource(issuesDelegate)
		issuesMenu.table.setDelegate(issuesDelegate)
		issuesMenu.delegate = self

		updateScrollBarWidth() // also updates menu
		prMenu.scrollToTop()
		issuesMenu.scrollToTop()
		prMenu.updateVibrancy()
		issuesMenu.updateVibrancy()
		startRateLimitHandling()

		NSUserNotificationCenter.defaultUserNotificationCenter().delegate = self

        var buildNumber = NSBundle.mainBundle().infoDictionary!["CFBundleVersion"] as! String
		let cav = "Version \(currentAppVersion) (\(buildNumber))"
		versionNumber.stringValue = cav

		if ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext) {
			startRefresh()
		} else if ApiServer.countApiServersInMoc(mainObjectContext) == 1, let a = ApiServer.allApiServersInMoc(mainObjectContext).first where a.authToken == nil || a.authToken!.isEmpty {
			startupAssistant()
		} else {
			preferencesSelected()
		}

		let n = NSNotificationCenter.defaultCenter()
		n.addObserver(self, selector: Selector("updateScrollBarWidth"), name: NSPreferredScrollerStyleDidChangeNotification, object: nil)
		n.addObserver(self, selector: Selector("updateImportExportSettings"), name: SETTINGS_EXPORTED, object: nil)

		addHotKeySupport()

		let s = SUUpdater.sharedUpdater()
		setUpdateCheckParameters()
		if !s.updateInProgress && Settings.checkForUpdatesAutomatically {
			s.checkForUpdatesInBackground()
		}
	}

	private func setupSortMethodMenu() {
		let m = NSMenu(title: "Sorting")
		if Settings.sortDescending {
			m.addItemWithTitle("Youngest First", action: Selector("sortMethodChanged:"), keyEquivalent: "")
			m.addItemWithTitle("Most Recently Active", action: Selector("sortMethodChanged:"), keyEquivalent: "")
			m.addItemWithTitle("Reverse Alphabetically", action: Selector("sortMethodChanged:"), keyEquivalent: "")
		} else {
			m.addItemWithTitle("Oldest First", action: Selector("sortMethodChanged:"), keyEquivalent: "")
			m.addItemWithTitle("Inactive For Longest", action: Selector("sortMethodChanged:"), keyEquivalent: "")
			m.addItemWithTitle("Alphabetically", action: Selector("sortMethodChanged:"), keyEquivalent: "")
		}
		sortModeSelect.menu = m
		sortModeSelect.selectItemAtIndex(Settings.sortMethod)
	}

	@IBAction func showLabelsSelected(sender: NSButton) {
		Settings.showLabels = (sender.integerValue==1)
		deferredUpdateTimer.push()
		updateLabelOptions()
		api.resetAllLabelChecks()
		if Settings.showLabels {
			for r in DataItem.allItemsOfType("Repo", inMoc: mainObjectContext) as! [Repo] {
				r.resetSyncState()
			}
			preferencesDirty = true
		}
	}

	@IBAction func dontConfirmRemoveAllMergedSelected(sender: NSButton) {
		Settings.dontAskBeforeWipingMerged = (sender.integerValue==1)
	}

	@IBAction func hideAllPrsSection(sender: NSButton) {
		Settings.hideAllPrsSection = (sender.integerValue==1)
		DataManager.postProcessAllItems()
		deferredUpdateTimer.push()
	}

	@IBAction func markUnmergeableOnUserSectionsOnlySelected(sender: NSButton) {
		Settings.markUnmergeableOnUserSectionsOnly = (sender.integerValue==1)
		deferredUpdateTimer.push()
	}

	@IBAction func displayRepositoryNameSelected(sender: NSButton) {
		Settings.showReposInName = (sender.integerValue==1)
		deferredUpdateTimer.push()
	}

	@IBAction func useVibrancySelected(sender: NSButton) {
		Settings.useVibrancy = (sender.integerValue==1)
		prMenu.updateVibrancy()
		issuesMenu.updateVibrancy()
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
			alert.informativeText = "Logging is a feature meant for error reporting, having it constantly enabled will cause this app to be less responsive and use more power"
			#endif
			alert.addButtonWithTitle("OK")
			alert.beginSheetModalForWindow(preferencesWindow, completionHandler: nil)
		}
	}

	@IBAction func includeLabelsInFilteringSelected(sender: NSButton) {
		Settings.includeLabelsInFilter = (sender.integerValue==1)
	}

	@IBAction func includeStatusesInFilteringSelected(sender: NSButton) {
		Settings.includeStatusesInFilter = (sender.integerValue==1)
	}

	@IBAction func includeRepositoriesInfilterSelected(sender: NSButton) {
		Settings.includeReposInFilter = (sender.integerValue==1)
	}

	@IBAction func dontConfirmRemoveAllClosedSelected(sender: NSButton) {
		Settings.dontAskBeforeWipingClosed = (sender.integerValue==1)
	}

	@IBAction func autoParticipateOnMentionSelected(sender: NSButton) {
		Settings.autoParticipateInMentions = (sender.integerValue==1)
		DataManager.postProcessAllItems()
		deferredUpdateTimer.push()
	}

	@IBAction func autoParticipateOnTeamMentionSelected(sender: NSButton) {
		Settings.autoParticipateOnTeamMentions = (sender.integerValue==1)
		DataManager.postProcessAllItems()
		deferredUpdateTimer.push()
	}

	@IBAction func dontKeepMyPrsSelected(sender: NSButton) {
		Settings.dontKeepPrsMergedByMe = (sender.integerValue==1)
	}

    @IBAction func grayOutWhenRefreshingSelected(sender: NSButton) {
        Settings.grayOutWhenRefreshing = (sender.integerValue==1)
    }

    @IBAction func disableAllCommentNotificationsSelected(sender: NSButton) {
        Settings.disableAllCommentNotifications = (sender.integerValue==1)
    }

	@IBAction func notifyOnStatusUpdatesSelected(sender: NSButton) {
		Settings.notifyOnStatusUpdates = (sender.integerValue==1)
	}

	@IBAction func notifyOnStatusUpdatesOnAllPrsSelected(sender: NSButton) {
		Settings.notifyOnStatusUpdatesForAllPrs = (sender.integerValue==1)
	}

	@IBAction func hideAvatarsSelected(sender: NSButton) {
		Settings.hideAvatars = (sender.integerValue==1)
		DataManager.postProcessAllItems()
		deferredUpdateTimer.push()
	}

	@IBAction func showIssuesMenuSelected(sender: NSButton) {
		Settings.showIssuesMenu = (sender.integerValue==1)
		DataManager.postProcessAllItems()
		if Settings.showIssuesMenu {
			for r in DataItem.allItemsOfType("Repo", inMoc: mainObjectContext) as! [Repo] {
				r.resetSyncState()
			}
			preferencesDirty = true
		} else {
			for i in DataItem.allItemsOfType("Issue", inMoc: mainObjectContext) as! [Issue] {
				i.postSyncAction = PostSyncAction.Delete.rawValue
			}
			DataItem.nukeDeletedItemsInMoc(mainObjectContext)
		}
		deferredUpdateTimer.push()
	}

	@IBAction func hidePrsSelected(sender: NSButton) {
		Settings.shouldHideUncommentedRequests = (sender.integerValue==1)
		DataManager.postProcessAllItems()
		deferredUpdateTimer.push()
	}

	@IBAction func showAllCommentsSelected(sender: NSButton) {
		Settings.showCommentsEverywhere = (sender.integerValue==1)
		DataManager.postProcessAllItems()
		deferredUpdateTimer.push()
	}

	@IBAction func sortOrderSelected(sender: NSButton) {
		Settings.sortDescending = (sender.integerValue==1)
		setupSortMethodMenu()
		DataManager.postProcessAllItems()
		deferredUpdateTimer.push()
	}

	@IBAction func countOnlyListedPrsSelected(sender: NSButton) {
		Settings.countOnlyListedPrs = (sender.integerValue==1)
		DataManager.postProcessAllItems()
		deferredUpdateTimer.push()
	}

	@IBAction func hideNewRespositoriesSelected(sender: NSButton) {
		Settings.hideNewRepositories = (sender.integerValue==1)
	}

	@IBAction func openPrAtFirstUnreadCommentSelected(sender: NSButton) {
		Settings.openPrAtFirstUnreadComment = (sender.integerValue==1)
	}

	@IBAction func sortMethodChanged(sender: AnyObject) {
		Settings.sortMethod = sortModeSelect.indexOfSelectedItem
		DataManager.postProcessAllItems()
		deferredUpdateTimer.push()
	}

	@IBAction func showStatusItemsSelected(sender: NSButton) {
		Settings.showStatusItems = (sender.integerValue==1)
		deferredUpdateTimer.push()
		updateStatusItemsOptions()

		api.resetAllStatusChecks()
		if Settings.showStatusItems {
			for r in DataItem.allItemsOfType("Repo", inMoc: mainObjectContext) as! [Repo] {
				r.resetSyncState()
			}
			preferencesDirty = true
		}
	}

	private func updateStatusItemsOptions() {
		let enable = Settings.showStatusItems
		makeStatusItemsSelectable.enabled = enable
		notifyOnStatusUpdates.enabled = enable
		notifyOnStatusUpdatesForAllPrs.enabled = enable
		statusTermMenu.enabled = enable
		statusTermsField.enabled = enable
		statusItemRefreshCounter.enabled = enable
		statusItemRescanLabel.alphaValue = enable ? 1.0 : 0.5
		statusItemsRefreshNote.alphaValue = enable ? 1.0 : 0.5

		let count = Settings.statusItemRefreshInterval
		statusItemRefreshCounter.integerValue = count
		statusItemRescanLabel.stringValue = count>1 ? "...and re-scan once every \(count) refreshes" : "...and re-scan on every refresh"
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
		deferredUpdateTimer.push()
	}

	@IBAction func showCreationSelected(sender: NSButton) {
		Settings.showCreatedInsteadOfUpdated = (sender.integerValue==1)
		DataManager.postProcessAllItems()
		deferredUpdateTimer.push()
	}

	@IBAction func groupbyRepoSelected(sender: NSButton) {
		Settings.groupByRepo = (sender.integerValue==1)
		deferredUpdateTimer.push()
	}

	@IBAction func moveAssignedPrsToMySectionSelected(sender: NSButton) {
		Settings.moveAssignedPrsToMySection = (sender.integerValue==1)
		DataManager.postProcessAllItems()
		deferredUpdateTimer.push()
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

	func userNotificationCenter(center: NSUserNotificationCenter, shouldPresentNotification notification: NSUserNotification) -> Bool {
		return true
	}

	func userNotificationCenter(center: NSUserNotificationCenter, didActivateNotification notification: NSUserNotification) {
		switch notification.activationType {
		case NSUserNotificationActivationType.ActionButtonClicked: fallthrough
		case NSUserNotificationActivationType.ContentsClicked:
			if let userInfo = notification.userInfo {
				var urlToOpen = userInfo[NOTIFICATION_URL_KEY] as? String
				if urlToOpen == nil {
					var relatedItem: ListableItem?
					if let itemId = DataManager.idForUriPath(userInfo[COMMENT_ID_KEY] as? String), c = mainObjectContext.existingObjectWithID(itemId, error: nil) as? PRComment {
						relatedItem = c.pullRequest ?? c.issue
						urlToOpen = c.webUrl
					} else if let itemId = DataManager.idForUriPath(userInfo[PULL_REQUEST_ID_KEY] as? String) {
						relatedItem = mainObjectContext.existingObjectWithID(itemId, error: nil) as? ListableItem
						urlToOpen = relatedItem?.webUrl
					} else if let itemId = DataManager.idForUriPath(userInfo[ISSUE_ID_KEY] as? String) {
						relatedItem = mainObjectContext.existingObjectWithID(itemId, error: nil) as? ListableItem
						urlToOpen = relatedItem?.webUrl
					}
					if let r = relatedItem {
						r.catchUpWithComments()
						DataManager.saveDB()
						if r is PullRequest {
							updatePrMenu()
						} else if r is Issue {
							updateIssuesMenu()
						}
					}
				}
				if let up = urlToOpen, u = NSURL(string: up) {
					NSWorkspace.sharedWorkspace().openURL(u)
				}
			}
		default: break
		}
		NSUserNotificationCenter.defaultUserNotificationCenter().removeDeliveredNotification(notification)
	}

	func postNotificationOfType(type: PRNotificationType, forItem: DataItem) {
		if preferencesDirty {
			return
		}

		let notification = NSUserNotification()
		notification.userInfo = DataManager.infoForType(type, item: forItem)

		switch type {
		case .NewMention:
			let c = forItem as! PRComment
			notification.title = "@" + (c.userName ?? "NoUserName") + " mentioned you:"
			notification.subtitle = c.notificationSubtitle()
			notification.informativeText = c.body
		case .NewComment:
			let c = forItem as! PRComment
			notification.title = "@" + (c.userName ?? "NoUserName") + " commented:"
			notification.subtitle = c.notificationSubtitle()
			notification.informativeText = c.body
		case .NewPr:
			notification.title = "New PR"
			notification.subtitle = (forItem as! PullRequest).title
		case .PrReopened:
			notification.title = "Re-Opened PR"
			notification.subtitle = (forItem as! PullRequest).title
		case .PrMerged:
			notification.title = "PR Merged!"
			notification.subtitle = (forItem as! PullRequest).title
		case .PrClosed:
			notification.title = "PR Closed"
			notification.subtitle = (forItem as! PullRequest).title
		case .NewRepoSubscribed:
			notification.title = "New Repository Subscribed"
			notification.subtitle = (forItem as! Repo).fullName
		case .NewRepoAnnouncement:
			notification.title = "New Repository"
			notification.subtitle = (forItem as! Repo).fullName
		case .NewPrAssigned:
			notification.title = "PR Assigned"
			notification.subtitle = (forItem as! PullRequest).title
		case .NewStatus:
			let c = forItem as! PRStatus
			notification.title = "PR Status Update"
			notification.subtitle = c.pullRequest.title
			notification.informativeText = c.descriptionText
		case .NewIssue:
			notification.title = "New Issue"
			notification.subtitle = (forItem as! Issue).title
		case .IssueReopened:
			notification.title = "Re-Opened Issue"
			notification.subtitle = (forItem as! Issue).title
		case .IssueClosed:
			notification.title = "Issue Closed"
			notification.subtitle = (forItem as! Issue).title
		case .NewIssueAssigned:
			notification.title = "Issue Assigned"
			notification.subtitle = (forItem as! Issue).title
		}

		if (type == .NewComment || type == .NewMention) && !Settings.hideAvatars && notification.respondsToSelector(Selector("setContentImage:")) {
			if let url = (forItem as! PRComment).avatarUrl {
				api.haveCachedAvatar(url) { image in
					notification.contentImage = image
					NSUserNotificationCenter.defaultUserNotificationCenter().deliverNotification(notification)
				}
			}
		} else { // proceed as normal
			NSUserNotificationCenter.defaultUserNotificationCenter().deliverNotification(notification)
		}
	}

	func dataItemSelected(item: ListableItem, alternativeSelect: Bool) {

		ignoreNextFocusLoss = alternativeSelect

		var urlToOpen = item.urlForOpening()
		item.catchUpWithComments()

		var window: MenuWindow

		if item is PullRequest {
			updatePrMenu()
			window = prMenu
		} else {
			updateIssuesMenu()
			window = issuesMenu
		}

		let reSelectIndex = alternativeSelect ? window.table.selectedRow : -1
		window.filter.becomeFirstResponder()

		if reSelectIndex > -1 && reSelectIndex < window.table.numberOfRows {
			window.table.selectRowIndexes(NSIndexSet(index: reSelectIndex), byExtendingSelection: false)
		}

		if let u = urlToOpen {
			NSWorkspace.sharedWorkspace().openURL(NSURL(string: u)!)
		}
	}

	func showMenu(menu: MenuWindow) {
		if !menu.visible, let v = menu.statusItem?.view as? StatusItemView {
			if menu == prMenu && issuesMenu.visible {
				closeMenu(issuesMenu)
			} else if menu == issuesMenu && prMenu.visible {
				closeMenu(prMenu)
			}
			v.highlighted = true
			sizeMenu(menu, andShow: true)
		}
	}

	private func setRefreshLabel(l: String) {
		prMenu.refreshMenuItem.title = l
		issuesMenu.refreshMenuItem.title = l
	}

	private func sizeMenu(window: MenuWindow, andShow: Bool) {

		if let siv = window.statusItem?.view as? StatusItemView {
			var menuLeft = siv.window!.frame.origin.x
			let screen = NSScreen.mainScreen()!
			let rightSide = screen.visibleFrame.origin.x + screen.visibleFrame.size.width
			let overflow = (menuLeft+MENU_WIDTH)-rightSide
			if overflow > 0 {
				menuLeft -= overflow
			}

			var menuHeight = TOP_HEADER_HEIGHT
			let rowCount = window.table.numberOfRows
			let screenHeight = screen.visibleFrame.size.height
			if rowCount==0 {
				menuHeight += 95
			} else {
				menuHeight += 10
				for f in 0..<rowCount {
					let rowView = window.table.viewAtColumn(0, row: f, makeIfNecessary: true) as! NSView
					menuHeight += rowView.frame.size.height + 2
					if menuHeight >= screenHeight {
						break
					}
				}
			}

			var bottom = screen.visibleFrame.origin.y
			if menuHeight < screenHeight {
				bottom += screenHeight-menuHeight
			} else {
				menuHeight = screenHeight
			}

			window.setFrame(CGRectMake(menuLeft, bottom, MENU_WIDTH, menuHeight), display: false, animate: false)

			if andShow {
				window.table.deselectAll(nil)
				opening = true
				window.level = Int(CGWindowLevelForKey(CGWindowLevelKey(kCGFloatingWindowLevelKey)))
				window.makeKeyAndOrderFront(self)
				NSApp.activateIgnoringOtherApps(true)
				opening = false
			}
		}
	}

	private func closeMenu(menu: MenuWindow) {
		if menu.visible, let siv = menu.statusItem?.view as? StatusItemView {
			siv.highlighted = false
			menu.orderOut(nil)
			menu.table.deselectAll(nil)
		}
	}

	func sectionHeaderRemoveSelected(headerTitle: String) {

		let inMenu = prMenu.visible ? prMenu : issuesMenu

		if inMenu == prMenu {
			if headerTitle == PullRequestSection.Merged.prMenuName() {
				if Settings.dontAskBeforeWipingMerged {
					removeAllMergedRequests()
				} else {
					let mergedRequests = PullRequest.allMergedRequestsInMoc(mainObjectContext)

					let alert = NSAlert()
					alert.messageText = "Clear \(mergedRequests.count) merged PRs?"
					alert.informativeText = "This will clear \(mergedRequests.count) merged PRs from your list.  This action cannot be undone, are you sure?"
					alert.addButtonWithTitle("No")
					alert.addButtonWithTitle("Yes")
					alert.showsSuppressionButton = true

					if alert.runModal()==NSAlertSecondButtonReturn {
						removeAllMergedRequests()
						if alert.suppressionButton!.state == NSOnState {
							Settings.dontAskBeforeWipingMerged = true
						}
					}
				}
			} else if headerTitle == PullRequestSection.Closed.prMenuName() {
				if Settings.dontAskBeforeWipingClosed {
					removeAllClosedRequests()
				} else {
					let closedRequests = PullRequest.allClosedRequestsInMoc(mainObjectContext)

					let alert = NSAlert()
					alert.messageText = "Clear \(closedRequests.count) closed PRs?"
					alert.informativeText = "This will remove \(closedRequests.count) closed PRs from your list.  This action cannot be undone, are you sure?"
					alert.addButtonWithTitle("No")
					alert.addButtonWithTitle("Yes")
					alert.showsSuppressionButton = true

					if alert.runModal()==NSAlertSecondButtonReturn {
						removeAllClosedRequests()
						if alert.suppressionButton!.state == NSOnState {
							Settings.dontAskBeforeWipingClosed = true
						}
					}
				}
			}
			if !prMenu.visible {
				showMenu(prMenu)
			}
		} else if inMenu == issuesMenu {
			if headerTitle == PullRequestSection.Closed.issuesMenuName() {
				if Settings.dontAskBeforeWipingClosed {
					removeAllClosedIssues()
				} else {
					let closedIssues = Issue.allClosedIssuesInMoc(mainObjectContext)

					let alert = NSAlert()
					alert.messageText = "Clear \(closedIssues.count) closed issues?"
					alert.informativeText = "This will remove \(closedIssues.count) closed issues from your list.  This action cannot be undone, are you sure?"
					alert.addButtonWithTitle("No")
					alert.addButtonWithTitle("Yes")
					alert.showsSuppressionButton = true

					if alert.runModal()==NSAlertSecondButtonReturn {
						removeAllClosedIssues()
						if alert.suppressionButton!.state == NSOnState {
							Settings.dontAskBeforeWipingClosed = true
						}
					}
				}
			}
			if !issuesMenu.visible {
				showMenu(issuesMenu)
			}
		}
	}

	private func removeAllMergedRequests() {
		for r in PullRequest.allMergedRequestsInMoc(mainObjectContext) {
			mainObjectContext.deleteObject(r)
		}
		DataManager.saveDB()
		updatePrMenu()
	}

	private func removeAllClosedRequests() {
		for r in PullRequest.allClosedRequestsInMoc(mainObjectContext) {
			mainObjectContext.deleteObject(r)
		}
		DataManager.saveDB()
		updatePrMenu()
	}

	private func removeAllClosedIssues() {
		for i in Issue.allClosedIssuesInMoc(mainObjectContext) {
			mainObjectContext.deleteObject(i)
		}
		DataManager.saveDB()
		updateIssuesMenu()
	}

	func unPinSelectedFor(item: DataItem) {
		mainObjectContext.deleteObject(item)
		DataManager.saveDB()
		if item is PullRequest {
			updatePrMenu()
		} else if item is Issue {
			updateIssuesMenu()
		}
	}

	private func startRateLimitHandling() {
		NSNotificationCenter.defaultCenter().addObserver(serverList, selector: Selector("reloadData"), name: API_USAGE_UPDATE, object: nil)
		api.updateLimitsFromServer()
	}

	@IBAction func refreshReposSelected(sender: NSButton?) {
		prepareForRefresh()
		controlTextDidChange(nil)

		let tempContext = DataManager.tempContext()
		api.fetchRepositoriesToMoc(tempContext) { [weak self] in

			if ApiServer.shouldReportRefreshFailureInMoc(tempContext) {
				var errorServers = [String]()
				for apiServer in ApiServer.allApiServersInMoc(tempContext) {
					if apiServer.goodToGo && !apiServer.syncIsGood {
						errorServers.append(apiServer.label ?? "NoServerName")
					}
				}

				let serverNames = ", ".join(errorServers)

				let alert = NSAlert()
				alert.messageText = "Error"
				alert.informativeText = "Could not refresh repository list from \(serverNames), please ensure that the tokens you are using are valid"
				alert.addButtonWithTitle("OK")
				alert.runModal()
			} else {
				tempContext.save(nil)
			}
			self!.completeRefresh()
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
		if let selectedServer = selectedServer(), index = indexOfObject(ApiServer.allApiServersInMoc(mainObjectContext), selectedServer) {
			mainObjectContext.deleteObject(selectedServer)
			serverList.reloadData()
			serverList.selectRowIndexes(NSIndexSet(index: min(index, serverList.numberOfRows-1)), byExtendingSelection: false)
			fillServerApiFormFromSelectedServer()
			deferredUpdateTimer.push()
			DataManager.saveDB()
		}
	}

	@IBAction func apiServerReportErrorSelected(sender: NSButton) {
		if let apiServer = selectedServer() {
			apiServer.reportRefreshFailures = (sender.integerValue != 0)
			storeApiFormToSelectedServer()
		}
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
			} else if obj===prMenu.filter {
				prFilterTimer.push()
			} else if obj===issuesMenu.filter {
				issuesFilterTimer.push()
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

	private func reset() {
		preferencesDirty = true
		api.resetAllStatusChecks()
		api.resetAllLabelChecks()
		Settings.lastSuccessfulRefresh = nil
		lastRepoCheck = never()
		projectsTable.reloadData()
		refreshButton.enabled = ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext)
		deferredUpdateTimer.push()
	}

	func markAllReadSelectedFrom(window: MenuWindow) {
		if window == prMenu {
			let f = PullRequest.requestForPullRequestsWithFilter(prMenu.filter.stringValue, sectionIndex: -1)
			for r in mainObjectContext.executeFetchRequest(f, error: nil) as! [PullRequest] {
				r.catchUpWithComments()
			}
			updatePrMenu()
		} else {
			let isf = Issue.requestForIssuesWithFilter(issuesMenu.filter.stringValue, sectionIndex: -1)
			for i in mainObjectContext.executeFetchRequest(isf, error: nil) as! [Issue] {
				i.catchUpWithComments()
			}
			updateIssuesMenu()
		}
	}

	private func preparePreferencesWindow() {
		serverList.selectRowIndexes(NSIndexSet(index: 0), byExtendingSelection: false)
		fillServerApiFormFromSelectedServer()

		api.updateLimitsFromServer()
		updateStatusTermPreferenceControls()
		commentAuthorBlacklist.objectValue = Settings.commentAuthorBlacklist

		sortModeSelect.selectItemAtIndex(Settings.sortMethod)
		prMergedPolicy.selectItemAtIndex(Settings.mergeHandlingPolicy)
		prClosedPolicy.selectItemAtIndex(Settings.closeHandlingPolicy)

		launchAtStartup.integerValue = StartupLaunch.isAppLoginItem() ? 1 : 0
		hideAllPrsSection.integerValue = Settings.hideAllPrsSection ? 1 : 0
		dontConfirmRemoveAllClosed.integerValue = Settings.dontAskBeforeWipingClosed ? 1 : 0
		displayRepositoryNames.integerValue = Settings.showReposInName ? 1 : 0
		includeRepositoriesInFiltering.integerValue = Settings.includeReposInFilter ? 1 : 0
		includeLabelsInFiltering.integerValue = Settings.includeLabelsInFilter ? 1 : 0
		includeStatusesInFiltering.integerValue = Settings.includeStatusesInFilter ? 1 : 0
		dontConfirmRemoveAllMerged.integerValue = Settings.dontAskBeforeWipingMerged ? 1 : 0
		hideUncommentedPrs.integerValue = Settings.shouldHideUncommentedRequests ? 1 : 0
		autoParticipateWhenMentioned.integerValue = Settings.autoParticipateInMentions ? 1 : 0
		autoParticipateOnTeamMentions.integerValue = Settings.autoParticipateOnTeamMentions ? 1 : 0
		hideAvatars.integerValue = Settings.hideAvatars ? 1 : 0
		dontKeepPrsMergedByMe.integerValue = Settings.dontKeepPrsMergedByMe ? 1 : 0
		grayOutWhenRefreshing.integerValue = Settings.grayOutWhenRefreshing ? 1 : 0
		notifyOnStatusUpdates.integerValue = Settings.notifyOnStatusUpdates ? 1 : 0
		notifyOnStatusUpdatesForAllPrs.integerValue = Settings.notifyOnStatusUpdatesForAllPrs ? 1 : 0
		disableAllCommentNotifications.integerValue = Settings.disableAllCommentNotifications ? 1 : 0
		showAllComments.integerValue = Settings.showCommentsEverywhere ? 1 : 0
		sortingOrder.integerValue = Settings.sortDescending ? 1 : 0
		showCreationDates.integerValue = Settings.showCreatedInsteadOfUpdated ? 1 : 0
		groupByRepo.integerValue = Settings.groupByRepo ? 1 : 0
		moveAssignedPrsToMySection.integerValue = Settings.moveAssignedPrsToMySection ? 1 : 0
		showStatusItems.integerValue = Settings.showStatusItems ? 1 : 0
		makeStatusItemsSelectable.integerValue = Settings.makeStatusItemsSelectable ? 1 : 0
		markUnmergeableOnUserSectionsOnly.integerValue = Settings.markUnmergeableOnUserSectionsOnly ? 1 : 0
		countOnlyListedPrs.integerValue = Settings.countOnlyListedPrs ? 1 : 0
		hideNewRepositories.integerValue = Settings.hideNewRepositories ? 1 : 0
		openPrAtFirstUnreadComment.integerValue = Settings.openPrAtFirstUnreadComment ? 1 : 0
		logActivityToConsole.integerValue = Settings.logActivityToConsole ? 1 : 0
		showLabels.integerValue = Settings.showLabels ? 1 : 0
		useVibrancy.integerValue = Settings.useVibrancy ? 1 : 0
		showIssuesMenu.integerValue = Settings.showIssuesMenu ? 1 : 0

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

		hotkeyEnable.enabled = true

		repoCheckStepper.floatValue = Settings.newRepoCheckPeriod
		newRepoCheckChanged(nil)

		refreshDurationStepper.floatValue = min(Settings.refreshPeriod, 3600)
		refreshDurationChanged(nil)

		projectsTable.reloadData()

		updateImportExportSettings()
	}

	func preferencesSelected() {
		refreshTimer?.invalidate()
		refreshTimer = nil

		preparePreferencesWindow()

		preferencesWindow.level = Int(CGWindowLevelForKey(CGWindowLevelKey(kCGFloatingWindowLevelKey)))
		preferencesWindow.makeKeyAndOrderFront(self)
	}

	func updateImportExportSettings() {
		repeatLastExportAutomatically.integerValue = Settings.autoRepeatSettingsExport ? 1 : 0
		if let lastExportDate = Settings.lastExportDate, fileName = Settings.lastExportUrl?.absoluteString, unescapedName = fileName.stringByReplacingPercentEscapesUsingEncoding(NSUTF8StringEncoding) {
			let time = itemDateFormatter.stringFromDate(lastExportDate)
			lastExportReport.stringValue = "Last exported \(time) to \(unescapedName)"
		} else {
			lastExportReport.stringValue = ""
		}
	}

	@IBAction func repeatLastExportSelected(sender: AnyObject) {
		Settings.autoRepeatSettingsExport = (repeatLastExportAutomatically.integerValue==1)
	}

	func application(sender: NSApplication, openFile filename: String) -> Bool {
		let url = NSURL(fileURLWithPath: filename)!
		let ext = filename.lastPathComponent.pathExtension
		if ext == "trailerSettings" {
			DLog("Will open %@", url.absoluteString)
			tryLoadSettings(url, skipConfirm: Settings.dontConfirmSettingsImport)
			return true
		}
		return false
	}

	func tryLoadSettings(url: NSURL, skipConfirm: Bool) -> Bool {
		if isRefreshing {
			let alert = NSAlert()
			alert.messageText = "Trailer is currently refreshing data, please wait until it's done and try importing your settings again"
			alert.addButtonWithTitle("OK")
			alert.runModal()
			return false

		} else if !skipConfirm {
			let alert = NSAlert()
			alert.messageText = "Import settings from this file?"
			alert.informativeText = "This will overwrite all your current Trailer settings, are you sure?"
			alert.addButtonWithTitle("No")
			alert.addButtonWithTitle("Yes")
			alert.showsSuppressionButton = true
			if alert.runModal()==NSAlertSecondButtonReturn {
				if alert.suppressionButton!.state == NSOnState {
					Settings.dontConfirmSettingsImport = true
				}
			} else {
				return false
			}
		}

		if !Settings.readFromURL(url) {
			let alert = NSAlert()
			alert.messageText = "The selected settings file could not be imported due to an error"
			alert.addButtonWithTitle("OK")
			alert.runModal()
			return false
		}
		DataManager.postProcessAllItems()
		DataManager.saveDB()
		preparePreferencesWindow()
		preferencesDirty = true
		startRefresh()

		return true
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
		s.beginSheetModalForWindow(preferencesWindow, completionHandler: { [weak self] response in
			if response == NSFileHandlingPanelOKButton, let url = s.URL {
				Settings.writeToURL(url)
				DLog("Exported settings to %@", url.absoluteString!)
			}
		})
	}

	@IBAction func importSettingsSelected(sender: NSButton) {
		let o = NSOpenPanel()
		o.title = "Import Settings From File..."
		o.prompt = "Import"
		o.nameFieldLabel = "Settings File"
		o.message = "Import Settings From File..."
		o.extensionHidden = false
		o.allowedFileTypes = ["trailerSettings"]
		o.beginSheetModalForWindow(preferencesWindow, completionHandler: { [weak self] response in
			if response == NSFileHandlingPanelOKButton, let url = o.URL {
				atNextEvent {
					self!.tryLoadSettings(url, skipConfirm: Settings.dontConfirmSettingsImport)
				}
			}
		})
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

	@IBAction func showAllRepositoriesSelected(sender: NSButton) {
		for r in Repo.reposForFilter(repoFilter.stringValue) {
			r.hidden = false
			r.resetSyncState()
		}
		preferencesDirty = true
		projectsTable.reloadData()
		Settings.possibleExport(nil)
	}

	@IBAction func hideAllRepositoriesSelected(sender: NSButton) {
		for r in Repo.reposForFilter(repoFilter.stringValue) {
			r.hidden = true
			r.dirty = false
		}
		preferencesDirty = true
		projectsTable.reloadData()
		Settings.possibleExport(nil)
	}

	@IBAction func enableHotkeySelected(sender: NSButton) {
		Settings.hotkeyEnable = hotkeyEnable.integerValue != 0
		Settings.hotkeyLetter = hotkeyLetter.titleOfSelectedItem ?? "T"
		Settings.hotkeyControlModifier = hotkeyControlModifier.integerValue != 0
		Settings.hotkeyCommandModifier = hotkeyCommandModifier.integerValue != 0
		Settings.hotkeyOptionModifier = hotkeyOptionModifier.integerValue != 0
		Settings.hotkeyShiftModifier = hotkeyShiftModifier.integerValue != 0
		enableHotkeySegments()
		addHotKeySupport()
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
	}

	@IBAction func prClosePolicySelected(sender: NSPopUpButton) {
		Settings.closeHandlingPolicy = sender.indexOfSelectedItem
	}

	/////////////////////////////////// Repo table

	private func repoForRow(row: Int) -> Repo {
		let parentCount = Repo.countParentRepos(repoFilter.stringValue)
		var r = row
		if r > parentCount {
			r--
		}
		let filteredRepos = Repo.reposForFilter(repoFilter.stringValue)
		return filteredRepos[r-1]
	}

	func tableViewSelectionDidChange(notification: NSNotification) {
		fillServerApiFormFromSelectedServer()
	}

	func tableView(tv: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		let cell = tableColumn!.dataCellForRow(row) as! NSCell

		if tv === projectsTable {
			if tableColumn?.identifier == "hide" {
				if tableView(tv, isGroupRow:row) {
					(cell as! NSButtonCell).imagePosition = NSCellImagePosition.NoImage
					cell.state = NSMixedState
					cell.enabled = false
				} else {
					(cell as! NSButtonCell).imagePosition = NSCellImagePosition.ImageOnly
					let r = repoForRow(row)
					cell.state = (r.hidden?.boolValue ?? false) ? NSOnState : NSOffState
					cell.enabled = true
				}
			} else {
				if tableView(tv, isGroupRow:row) {
					cell.title = row==0 ? "Parent Repositories" : "Forked Repositories"
					cell.state = NSMixedState
					cell.enabled = false
				}
				else
				{
					let r = repoForRow(row)
					let repoName = r.fullName ?? "NoRepoName"
					cell.title = (r.inaccessible?.boolValue ?? false) ? repoName + " (inaccessible)" : repoName
					cell.enabled = true
				}
			}
		}
		else
		{
			let allServers = ApiServer.allApiServersInMoc(mainObjectContext)
			let apiServer = allServers[row]
			if tableColumn?.identifier == "server" {
				cell.title = apiServer.label ?? "NoApiServer"
			} else { // api usage
				let c = cell as! NSLevelIndicatorCell
				c.minValue = 0
				let rl = apiServer.requestsLimit?.doubleValue ?? 0.0
				c.maxValue = rl
				c.warningValue = rl*0.5
				c.criticalValue = rl*0.8
				c.doubleValue = rl - (apiServer.requestsRemaining?.doubleValue ?? 0)
			}
		}
		return cell
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
		} else if tableView === prMenu.table {
			let f = PullRequest.requestForPullRequestsWithFilter(prMenu.filter.stringValue, sectionIndex: -1)
			return mainObjectContext.countForFetchRequest(f, error: nil)
		} else {
			return ApiServer.countApiServersInMoc(mainObjectContext)
		}
	}

	func tableView(tv: NSTableView, setObjectValue object: AnyObject?, forTableColumn tableColumn: NSTableColumn?, row: Int) {
		if tv === projectsTable {
			if !tableView(tv, isGroupRow: row) {
				let r = repoForRow(row)
				let hideNow = object?.boolValue ?? false
				r.hidden = hideNow
				r.dirty = !hideNow
			}
			DataManager.saveDB()
			preferencesDirty = true
			Settings.possibleExport(nil)
		}
	}

	func applicationShouldTerminate(sender: NSApplication) -> NSApplicationTerminateReply {
		DataManager.saveDB()
		return NSApplicationTerminateReply.TerminateNow
	}

	func windowDidBecomeKey(notification: NSNotification) {
		if let window = notification.object as? MenuWindow {
			if ignoreNextFocusLoss {
				ignoreNextFocusLoss = false
			} else {
				window.scrollToTop()
				window.table.deselectAll(nil)
			}
			window.filter.becomeFirstResponder()
		}
	}

	func windowDidResignKey(notification: NSNotification) {
		if ignoreNextFocusLoss {
			showMenu(notification.object as! MenuWindow)
			return
		}
		if !opening {
			if notification.object === prMenu {
				closeMenu(prMenu)
			} else if notification.object === issuesMenu {
				closeMenu(issuesMenu)
			}
		}
	}

	func windowWillClose(notification: NSNotification) {
		if notification.object === preferencesWindow {
			controlTextDidChange(nil)
			if ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext) && preferencesDirty {
				startRefresh()
			} else {
				if refreshTimer == nil && Settings.refreshPeriod > 0.0 {
					startRefreshIfItIsDue()
				}
			}
			setUpdateCheckParameters()
		}
	}
	
	private func setUpdateCheckParameters() {
		let s = SUUpdater.sharedUpdater()
		let autoCheck = Settings.checkForUpdatesAutomatically
		s.automaticallyChecksForUpdates = autoCheck
		if autoCheck {
			s.updateCheckInterval = NSTimeInterval(3600)*NSTimeInterval(Settings.checkForUpdatesInterval)
		}
		DLog("Check for updates set to %d every %f seconds", s.automaticallyChecksForUpdates, s.updateCheckInterval)
	}

	func startRefreshIfItIsDue() {

		if let l = Settings.lastSuccessfulRefresh {
			let howLongAgo = NSDate().timeIntervalSinceDate(l)
			if howLongAgo > NSTimeInterval(Settings.refreshPeriod) {
				startRefresh()
			} else {
				let howLongUntilNextSync = NSTimeInterval(Settings.refreshPeriod) - howLongAgo
				DLog("No need to refresh yet, will refresh in %f", howLongUntilNextSync)
				refreshTimer = NSTimer.scheduledTimerWithTimeInterval(howLongUntilNextSync, target: self, selector: Selector("refreshTimerDone"), userInfo: nil, repeats: false)
			}
		}
		else
		{
			startRefresh()
		}
	}

	private func checkApiUsage() {
		for apiServer in ApiServer.allApiServersInMoc(mainObjectContext) {
			if apiServer.requestsLimit?.doubleValue > 0 {
				if apiServer.requestsRemaining?.doubleValue == 0 {
					let apiLabel = apiServer.label ?? "NoApiServerLabel"
					let dateFormatter = NSDateFormatter()
					dateFormatter.doesRelativeDateFormatting = true
					dateFormatter.dateStyle = NSDateFormatterStyle.MediumStyle
					dateFormatter.timeStyle = NSDateFormatterStyle.MediumStyle
					let resetDateString = apiServer.resetDate == nil ? "(unspecified date)" : dateFormatter.stringFromDate(apiServer.resetDate!)

					let alert = NSAlert()
					alert.messageText = "Your API request usage for '\(apiLabel)' is over the limit!"
					alert.informativeText = "Your request cannot be completed until your hourly API allowance is reset \(resetDateString).\n\nIf you get this error often, try to make fewer manual refreshes or reducing the number of repos you are monitoring.\n\nYou can check your API usage at any time from 'Servers' preferences pane at any time."
					alert.addButtonWithTitle("OK")
					alert.runModal()
				} else if ((apiServer.requestsRemaining?.doubleValue ?? 0.0) / (apiServer.requestsLimit?.doubleValue ?? 1.0)) < LOW_API_WARNING {
					let apiLabel = apiServer.label ?? "NoApiServerLabel"
					let dateFormatter = NSDateFormatter()
					dateFormatter.doesRelativeDateFormatting = true
					dateFormatter.dateStyle = NSDateFormatterStyle.MediumStyle
					dateFormatter.timeStyle = NSDateFormatterStyle.MediumStyle
					let resetDateString = apiServer.resetDate == nil ? "(unspecified date)" : dateFormatter.stringFromDate(apiServer.resetDate!)

					let alert = NSAlert()
					alert.messageText = "Your API request usage for '\(apiLabel)' is close to full"
					alert.informativeText = "Try to make fewer manual refreshes, increasing the automatic refresh time, or reducing the number of repos you are monitoring.\n\nYour allowance will be reset by Github \(resetDateString).\n\nYou can check your API usage from the 'Servers' preferences pane at any time."
					alert.addButtonWithTitle("OK")
					alert.runModal()
				}
			}
		}
	}

	func tabView(tabView: NSTabView, willSelectTabViewItem tabViewItem: NSTabViewItem?) {
		if tabView.indexOfTabViewItem(tabViewItem!) == 1 {
			if (lastRepoCheck.isEqualToDate(never()) || Repo.countVisibleReposInMoc(mainObjectContext) == 0) && ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext) {
				refreshReposSelected(nil)
			}
		}
	}

	private func prepareForRefresh() {
		refreshTimer?.invalidate()
		refreshTimer = nil

		refreshButton.enabled = false
		projectsTable.enabled = false
		activityDisplay.startAnimation(nil)
		(prMenu.statusItem?.view as? StatusItemView)?.grayOut = Settings.grayOutWhenRefreshing
		(issuesMenu.statusItem?.view as? StatusItemView)?.grayOut = Settings.grayOutWhenRefreshing

		api.expireOldImageCacheEntries()
		DataManager.postMigrationTasks()

		isRefreshing = true

		if prMenu.messageView != nil {
			updatePrMenu()
		}

		if issuesMenu.messageView != nil {
			updateIssuesMenu()
		}

		setRefreshLabel(" Refreshing...")

		DLog("Starting refresh")
	}

	private func completeRefresh() {
		isRefreshing = false
		preferencesDirty = false
		refreshButton.enabled = true
		projectsTable.enabled = true
		activityDisplay.stopAnimation(nil)
		DataManager.saveDB()
		projectsTable.reloadData()
		updatePrMenu()
		updateIssuesMenu()
		checkApiUsage()
		DataManager.saveDB()
		DataManager.sendNotifications()
		DLog("Refresh done")
	}

	func startRefresh() {
		if isRefreshing || api.currentNetworkStatus == NetworkStatus.NotReachable || !ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext) {
			return
		}

		prepareForRefresh()

		let oldPrTarget: AnyObject? = prMenu.refreshMenuItem.target
		let oldPrAction = prMenu.refreshMenuItem.action
		prMenu.refreshMenuItem.action = nil
		prMenu.refreshMenuItem.target = nil
		let oldIssuesTarget: AnyObject? = issuesMenu.refreshMenuItem.target
		let oldIssuesAction = issuesMenu.refreshMenuItem.action
		issuesMenu.refreshMenuItem.action = nil
		issuesMenu.refreshMenuItem.target = nil

		api.syncItemsForActiveReposAndCallback { [weak self] in

			self!.prMenu.refreshMenuItem.target = oldPrTarget
			self!.prMenu.refreshMenuItem.action = oldPrAction
			self!.issuesMenu.refreshMenuItem.target = oldIssuesTarget
			self!.issuesMenu.refreshMenuItem.action = oldIssuesAction

			if !ApiServer.shouldReportRefreshFailureInMoc(mainObjectContext) {
				Settings.lastSuccessfulRefresh = NSDate()
			}
			self!.completeRefresh()
			self!.refreshTimer = NSTimer.scheduledTimerWithTimeInterval(NSTimeInterval(Settings.refreshPeriod), target: self!, selector: Selector("refreshTimerDone"), userInfo: nil, repeats: false)
		}
	}

	@IBAction func refreshDurationChanged(sender: NSStepper?) {
		Settings.refreshPeriod = refreshDurationStepper.floatValue
		refreshDurationLabel.stringValue = "Refresh PRs every \(refreshDurationStepper.integerValue) seconds"
	}

	@IBAction func newRepoCheckChanged(sender: NSStepper?) {
		Settings.newRepoCheckPeriod = repoCheckStepper.floatValue
		repoCheckLabel.stringValue = "Refresh repositories every \(repoCheckStepper.integerValue) hours"
	}

	func refreshTimerDone() {
		if ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext) && Repo.countVisibleReposInMoc(mainObjectContext) > 0 {
			startRefresh()
		}
	}

	func updateIssuesMenu() {

		if Settings.showIssuesMenu {
			issuesMenu.showStatusItem()
		} else {
			issuesMenu.hideStatusItem()
			return
		}

		var countString: String
		var attributes: [String : AnyObject]
		if ApiServer.shouldReportRefreshFailureInMoc(mainObjectContext) {
			countString = "X"
			attributes = [ NSFontAttributeName: NSFont.boldSystemFontOfSize(10),
				NSForegroundColorAttributeName: MAKECOLOR(0.8, 0.0, 0.0, 1.0) ]
		} else {
			let f = Issue.requestForIssuesWithFilter(issuesMenu.filter.stringValue, sectionIndex: -1)
			countString = String(mainObjectContext.countForFetchRequest(f, error: nil))

			if Issue.badgeCountInMoc(mainObjectContext) > 0 {
				attributes = [ NSFontAttributeName: NSFont.menuBarFontOfSize(10),
					NSForegroundColorAttributeName: MAKECOLOR(0.8, 0.0, 0.0, 1.0) ]
			} else {
				attributes = [ NSFontAttributeName: NSFont.menuBarFontOfSize(10),
					NSForegroundColorAttributeName: NSColor.controlTextColor() ]
			}
		}

		DLog("Updating issues menu, \(countString) total items")

		let width = countString.sizeWithAttributes(attributes).width

		let statusBar = NSStatusBar.systemStatusBar()
		let H = statusBar.thickness
		let length = H + width + STATUSITEM_PADDING*3
		var updateStatusItem = true
		let shouldGray = Settings.grayOutWhenRefreshing && isRefreshing

		if let s = issuesMenu.statusItem?.view as? StatusItemView where compareDict(s.textAttributes, to: attributes) && s.statusLabel == countString && s.grayOut == shouldGray {
			updateStatusItem = false
		}

		if updateStatusItem {
			dispatch_async(dispatch_get_main_queue()) { [weak self] in
				DLog("Updating issues status item");
				let siv = StatusItemView(frame: CGRectMake(0, 0, length+2, H), label: countString, prefix: "issues", attributes: attributes)
				siv.labelOffset = 2
				siv.highlighted = self!.issuesMenu.visible
				siv.grayOut = shouldGray
				siv.tappedCallback = { [weak self] in
					let m = self!.issuesMenu
					if m.visible {
						self!.closeMenu(m)
					} else {
						self!.showMenu(m)
					}
					return
				}
				self!.issuesMenu.statusItem?.view = siv
			}
		}

		issuesDelegate.reloadData(issuesMenu.filter.stringValue)
		issuesMenu.table.reloadData()

		issuesMenu.messageView?.removeFromSuperview()

		if issuesMenu.table.numberOfRows == 0 {
			issuesMenu.messageView = MessageView(frame: CGRectMake(0, 0, MENU_WIDTH, 100), message: DataManager.reasonForEmptyIssuesWithFilter(issuesMenu.filter.stringValue))
			issuesMenu.contentView.addSubview(issuesMenu.messageView!)
		}

		sizeMenu(issuesMenu, andShow: false)
	}

	func updatePrMenu() {

		prMenu.showStatusItem()

		var countString: String
		var attributes: [String : AnyObject]
		if ApiServer.shouldReportRefreshFailureInMoc(mainObjectContext) {
			countString = "X"
			attributes = [ NSFontAttributeName: NSFont.boldSystemFontOfSize(10),
				NSForegroundColorAttributeName: MAKECOLOR(0.8, 0.0, 0.0, 1.0) ]
		} else {
			if Settings.countOnlyListedPrs {
				let f = PullRequest.requestForPullRequestsWithFilter(prMenu.filter.stringValue, sectionIndex: -1)
				countString = String(mainObjectContext.countForFetchRequest(f, error: nil))
			} else {
				countString = String(PullRequest.countOpenRequestsInMoc(mainObjectContext))
			}

			if PullRequest.badgeCountInMoc(mainObjectContext) > 0 {
				attributes = [ NSFontAttributeName: NSFont.menuBarFontOfSize(10),
					NSForegroundColorAttributeName: MAKECOLOR(0.8, 0.0, 0.0, 1.0) ]
			} else {
				attributes = [ NSFontAttributeName: NSFont.menuBarFontOfSize(10),
					NSForegroundColorAttributeName: NSColor.controlTextColor() ]
			}
		}

		DLog("Updating PR menu, \(countString) total items")

		let width = countString.sizeWithAttributes(attributes).width

		let statusBar = NSStatusBar.systemStatusBar()
		let H = statusBar.thickness
		let length = H + width + STATUSITEM_PADDING*3
        var updateStatusItem = true
        let shouldGray = Settings.grayOutWhenRefreshing && isRefreshing
		if let s = prMenu.statusItem?.view as? StatusItemView where compareDict(s.textAttributes, to: attributes) && s.statusLabel == countString && s.grayOut == shouldGray {
			updateStatusItem = false
		}

        if updateStatusItem {
			dispatch_async(dispatch_get_main_queue()) { [weak self] in
				DLog("Updating PR status item");
				let siv = StatusItemView(frame: CGRectMake(0, 0, length, H), label: countString, prefix: "pr", attributes: attributes)
				siv.highlighted = self!.prMenu.visible
				siv.grayOut = shouldGray
				siv.tappedCallback = { [weak self] in
					let m = self!.prMenu
					if m.visible {
						self!.closeMenu(m)
					} else {
						self!.showMenu(m)
					}
					return
				}
				self!.prMenu.statusItem?.view = siv
			}
        }

		pullRequestDelegate.reloadData(prMenu.filter.stringValue)
		prMenu.table.reloadData()

		prMenu.messageView?.removeFromSuperview()

		if prMenu.table.numberOfRows == 0 {
			prMenu.messageView = MessageView(frame: CGRectMake(0, 0, MENU_WIDTH, 100), message: DataManager.reasonForEmptyWithFilter(prMenu.filter.stringValue))
			prMenu.contentView.addSubview(prMenu.messageView!)
		}

		sizeMenu(prMenu, andShow: false)
	}

	private func compareDict(from: [String : AnyObject], to: [String : AnyObject]) -> Bool {
        for (key, value) in from {
            if let v: AnyObject = to[key] {
                if !v.isEqual(value) {
                    return false
                }
            } else {
                return false
            }
        }
        return true
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
			statusTermsField.alphaValue = 0.8
		}
		statusTermsField.objectValue = Settings.statusFilteringTerms
	}

	@IBAction func statusFilterMenuChanged(sender: NSPopUpButton) {
		Settings.statusFilteringMode = sender.indexOfSelectedItem
		Settings.statusFilteringTerms = statusTermsField.objectValue as! [String]
		updateStatusTermPreferenceControls()
		deferredUpdateTimer.push()
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
		if let index = indexOfObject(ApiServer.allApiServersInMoc(mainObjectContext), a) {
			serverList.selectRowIndexes(NSIndexSet(index: index), byExtendingSelection: false)
			fillServerApiFormFromSelectedServer()
		}
	}

	/////////////////////// keyboard shortcuts

	private func addHotKeySupport() {
		if Settings.hotkeyEnable {
			if globalKeyMonitor == nil {
				let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
				let options = [key: NSNumber(bool: (AXIsProcessTrusted() == 0))]
				if AXIsProcessTrustedWithOptions(options) != 0 {
					globalKeyMonitor = NSEvent.addGlobalMonitorForEventsMatchingMask(NSEventMask.KeyDownMask, handler: { [weak self] incomingEvent in
						self!.checkForHotkey(incomingEvent)
						return
					})
				}
			}
		} else {
			if globalKeyMonitor != nil {
				NSEvent.removeMonitor(globalKeyMonitor!)
				globalKeyMonitor = nil
			}
		}

		if localKeyMonitor != nil {
			return
		}

		localKeyMonitor = NSEvent.addLocalMonitorForEventsMatchingMask(NSEventMask.KeyDownMask, handler: { [weak self] (incomingEvent) -> NSEvent! in

			if self!.checkForHotkey(incomingEvent) {
				return nil
			}

			if let w = incomingEvent.window as? MenuWindow {
				//DLog("Keycode: %d", incomingEvent.keyCode)
				switch incomingEvent.keyCode {
				case 123: // left
					fallthrough
				case 124: // right
					if app.isManuallyScrolling && w.table.selectedRow == -1 { return nil }
					if Settings.showIssuesMenu {
						if w == self!.prMenu {
							self!.showMenu(self!.issuesMenu)
						} else if w == self!.issuesMenu {
							self!.showMenu(self!.prMenu)
						}
					}
					return nil
				case 125: // down
					if app.isManuallyScrolling && w.table.selectedRow == -1 { return nil }
					var i = w.table.selectedRow + 1
					if i < w.table.numberOfRows {
						while self!.dataItemAtRow(i, inMenu: w) == nil { i++ }
						self!.scrollToIndex(i, inMenu: w)
					}
					return nil
				case 126: // up
					if app.isManuallyScrolling && w.table.selectedRow == -1 { return nil }
					var i = w.table.selectedRow - 1
					if i > 0 {
						while self!.dataItemAtRow(i, inMenu: w) == nil { i-- }
						self!.scrollToIndex(i, inMenu: w)
					}
					return nil
				case 36: // enter
					if app.isManuallyScrolling && w.table.selectedRow == -1 { return nil }
					if let dataItem = self!.dataItemAtRow(w.table.selectedRow, inMenu: w) {
						let isAlternative = ((incomingEvent.modifierFlags & NSEventModifierFlags.AlternateKeyMask) == NSEventModifierFlags.AlternateKeyMask)
						self!.dataItemSelected(dataItem, alternativeSelect: isAlternative)
					}
					return nil
				case 53: // escape
					self!.closeMenu(w)
					return nil
				default:
					break
				}
			}
			return incomingEvent
		})
	}

	private func dataItemAtRow(row: Int, inMenu: MenuWindow) -> ListableItem? {
		if inMenu == prMenu {
			return pullRequestDelegate.pullRequestAtRow(row)
		} else if inMenu == issuesMenu {
			return issuesDelegate.issueAtRow(row)
		} else {
			return nil
		}
	}

	private func scrollToIndex(i: Int, inMenu: MenuWindow) {
		app.isManuallyScrolling = true
		mouseIgnoreTimer.push()
		inMenu.table.scrollRowToVisible(i)
		dispatch_async(dispatch_get_main_queue(), { [weak self] in
			inMenu.table.selectRowIndexes(NSIndexSet(index: i), byExtendingSelection: false)
			return
		})
	}

	func focusedItemUrl() -> String? {
		if prMenu.visible {
			let row = prMenu.table.selectedRow
			var pr: PullRequest?
			if row >= 0 {
				prMenu.table.deselectAll(nil)
				pr = pullRequestDelegate.pullRequestAtRow(row)
			}
			atNextEvent { [weak self] in
				self!.prMenu.table.selectRowIndexes(NSIndexSet(index: row), byExtendingSelection: false)
			}
			return pr?.webUrl
		} else if issuesMenu.visible {
			let row = issuesMenu.table.selectedRow
			var i: Issue?
			if row >= 0 {
				issuesMenu.table.deselectAll(nil)
				i = issuesDelegate.issueAtRow(row)
			}
			atNextEvent { [weak self] in
				self!.issuesMenu.table.selectRowIndexes(NSIndexSet(index: row), byExtendingSelection: false)
			}
			return i?.webUrl
		} else {
			return nil
		}
	}

	private func checkForHotkey(incomingEvent: NSEvent) -> Bool {
		var check = 0

		if Settings.hotkeyCommandModifier {
			check += (incomingEvent.modifierFlags & NSEventModifierFlags.CommandKeyMask) == NSEventModifierFlags.CommandKeyMask ? 1 : -1
		} else {
			check += (incomingEvent.modifierFlags & NSEventModifierFlags.CommandKeyMask) == NSEventModifierFlags.CommandKeyMask ? -1 : 1
		}

		if Settings.hotkeyControlModifier {
			check += (incomingEvent.modifierFlags & NSEventModifierFlags.ControlKeyMask) == NSEventModifierFlags.ControlKeyMask ? 1 : -1
		} else {
			check += (incomingEvent.modifierFlags & NSEventModifierFlags.ControlKeyMask) == NSEventModifierFlags.ControlKeyMask ? -1 : 1
		}

		if Settings.hotkeyOptionModifier {
			check += (incomingEvent.modifierFlags & NSEventModifierFlags.AlternateKeyMask) == NSEventModifierFlags.AlternateKeyMask ? 1 : -1
		} else {
			check += (incomingEvent.modifierFlags & NSEventModifierFlags.AlternateKeyMask) == NSEventModifierFlags.AlternateKeyMask ? -1 : 1
		}

		if Settings.hotkeyShiftModifier {
			check += (incomingEvent.modifierFlags & NSEventModifierFlags.ShiftKeyMask) == NSEventModifierFlags.ShiftKeyMask ? 1 : -1
		} else {
			check += (incomingEvent.modifierFlags & NSEventModifierFlags.ShiftKeyMask) == NSEventModifierFlags.ShiftKeyMask ? -1 : 1
		}

		let keyMap = [
			"A": 0, "B": 11, "C": 8, "D": 2, "E": 14, "F": 3, "G": 5, "H": 4, "I": 34, "J": 38,
			"K": 40, "L": 37, "M": 46, "N": 45, "O": 31, "P": 35, "Q": 12, "R": 15, "S": 1,
			"T": 17, "U": 32, "V": 9, "W": 13, "X": 7, "Y": 16, "Z": 6 ];

		if check==4, let n = keyMap[Settings.hotkeyLetter] where incomingEvent.keyCode == UInt16(n) {
			showMenu(prMenu)
			return true
		}
		return false
	}
	
	////////////// scrollbars
	
	func updateScrollBarWidth() {
		if let s = prMenu.scrollView.verticalScroller {
			if s.scrollerStyle == NSScrollerStyle.Legacy {
				scrollBarWidth = s.frame.size.width
			} else {
				scrollBarWidth = 0
			}
		}
		updatePrMenu()
		updateIssuesMenu()
	}

	////////////////////// windows

	private var startupAssistantController: NSWindowController?
	private func startupAssistant() {
		if startupAssistantController == nil {
			startupAssistantController = NSWindowController(windowNibName:"SetupAssistant")
			if let w = startupAssistantController!.window as? SetupAssistant {
				w.level = Int(CGWindowLevelForKey(CGWindowLevelKey(kCGFloatingWindowLevelKey)))
				w.center()
				w.makeKeyAndOrderFront(self)
			}
		}
	}
	func closedSetupAssistant() {
		startupAssistantController = nil
	}

	private var aboutWindowController: NSWindowController?
	func showAboutWindow() {
		if aboutWindowController == nil {
			aboutWindowController = NSWindowController(windowNibName:"AboutWindow")
		}
		if let w = aboutWindowController!.window as? AboutWindow {
			w.level = Int(CGWindowLevelForKey(CGWindowLevelKey(kCGFloatingWindowLevelKey)))
			w.version.stringValue = versionNumber.stringValue
			w.center()
			w.makeKeyAndOrderFront(self)
		}
	}
	func closedAboutWindow() {
		aboutWindowController = nil
	}

	//////////////////////// Dark mode

	var darkMode: Bool = false {
		didSet {
			if darkMode != oldValue {
				prMenu.statusItem?.view = nil
				prMenu.updateVibrancy()
				updatePrMenu()

				issuesMenu.statusItem?.view = nil
				issuesMenu.updateVibrancy()
				updateIssuesMenu()
			}
		}
	}

	func checkDarkMode() {
		atNextEvent { [weak self] in
			if NSAppKitVersionNumber>Double(NSAppKitVersionNumber10_9) {
				let c = NSAppearance.currentAppearance()
				if c.respondsToSelector(Selector("allowsVibrancy")) {
					self!.darkMode = c.name.rangeOfString(NSAppearanceNameVibrantDark) != nil
					return
				}
			}
			self!.darkMode = false
		}
	}

	private func setupDarkModeMonitoring() {
		NSDistributedNotificationCenter.defaultCenter().addObserver(self, selector: Selector("checkDarkMode"), name: "AppleInterfaceThemeChangedNotification", object: nil)
		checkDarkMode()
	}
}
