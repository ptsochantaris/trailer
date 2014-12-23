
var app: OSX_AppDelegate!

class OSX_AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSUserNotificationCenterDelegate, NSTableViewDelegate, NSTableViewDataSource, NSTabViewDelegate {

	// Preferences window
	@IBOutlet var preferencesWindow: NSWindow!
	@IBOutlet var refreshButton: NSButton!
	@IBOutlet var activityDisplay: NSProgressIndicator!
	@IBOutlet var projectsTable: NSTableView!
	@IBOutlet var refreshNow: NSMenuItem!
	@IBOutlet var versionNumber: NSTextField!
	@IBOutlet var launchAtStartup: NSButton!
	@IBOutlet var refreshDurationLabel: NSTextField!
	@IBOutlet var refreshDurationStepper: NSStepper!
	@IBOutlet var hideUncommentedPrs: NSButton!
	@IBOutlet var repoFilter: NSTextField!
	@IBOutlet var showAllComments: NSButton!
	@IBOutlet var sortingOrder: NSButton!
	@IBOutlet var sortModeSelect: NSPopUpButton!
	@IBOutlet var showCreationDates: NSButton!
	@IBOutlet var dontKeepPrsMergedByMe: NSButton!
	@IBOutlet var hideAvatars: NSButton!
	@IBOutlet var autoParticipateWhenMentioned: NSButton!
	@IBOutlet var dontConfirmRemoveAllMerged: NSButton!
	@IBOutlet var dontConfirmRemoveAllClosed: NSButton!
	@IBOutlet var displayRepositoryNames: NSButton!
	@IBOutlet var includeRepositoriesInFiltering: NSButton!
	@IBOutlet var groupByRepo: NSButton!
	@IBOutlet var hideAllPrsSection: NSButton!
	@IBOutlet var showStatusItems: NSButton!
	@IBOutlet var makeStatusItemsSelectable: NSButton!
	@IBOutlet var statusTermMenu: NSPopUpButton!
	@IBOutlet var statusTermsField: NSTokenField!
	@IBOutlet var moveAssignedPrsToMySection: NSButton!
	@IBOutlet var markUnmergeableOnUserSectionsOnly: NSButton!
	@IBOutlet var repoCheckLabel: NSTextField!
	@IBOutlet var repoCheckStepper: NSStepper!
	@IBOutlet var countOnlyListedPrs: NSButton!
	@IBOutlet var prMergedPolicy: NSPopUpButton!
	@IBOutlet var prClosedPolicy: NSPopUpButton!
	@IBOutlet var checkForUpdatesAutomatically: NSButton!
	@IBOutlet var checkForUpdatesLabel: NSTextField!
	@IBOutlet var checkForUpdatesSelector: NSStepper!
	@IBOutlet var statusItemRescanLabel: NSTextField!
	@IBOutlet var statusItemRefreshCounter: NSStepper!
	@IBOutlet var statusItemsRefreshNote: NSTextField!
	@IBOutlet var hideNewRepositories: NSButton!
	@IBOutlet var openPrAtFirstUnreadComment: NSButton!
	@IBOutlet var logActivityToConsole: NSButton!
	@IBOutlet var commentAuthorBlacklist: NSTokenField!
	@IBOutlet var showLabels: NSButton!

	// Preferences - Display
	@IBOutlet var useVibrancy: NSButton!
	@IBOutlet var includeLabelsInFiltering: NSButton!

	// Preferences - Labels
	@IBOutlet var labelRescanLabel: NSTextField!
	@IBOutlet var labelRefreshNote: NSTextField!
	@IBOutlet var labelRefreshCounter: NSStepper!

	// Preferences - Servers
	@IBOutlet var serverList: NSTableView!
	@IBOutlet var apiServerName: NSTextField!
	@IBOutlet var apiServerApiPath: NSTextField!
	@IBOutlet var apiServerWebPath: NSTextField!
	@IBOutlet var apiServerAuthToken: NSTextField!
	@IBOutlet var apiServerSelectedBox: NSBox!
	@IBOutlet var apiServerTestButton: NSButton!
	@IBOutlet var apiServerDeleteButton: NSButton!
	@IBOutlet var apiServerReportError: NSButton!

	// Keyboard
	@IBOutlet var hotkeyEnable: NSButton!
	@IBOutlet var hotkeyCommandModifier: NSButton!
	@IBOutlet var hotkeyOptionModifier: NSButton!
	@IBOutlet var hotkeyShiftModifier: NSButton!
	@IBOutlet var hotkeyLetter: NSPopUpButton!
	@IBOutlet var hotKeyHelp: NSTextField!
	@IBOutlet var hotKeyContainer: NSBox!
	@IBOutlet var hotkeyControlModifier: NSButton!

	// About window
	@IBOutlet var aboutVersion: NSTextField!
	
	// Menu
	var statusItem: NSStatusItem!
	@IBOutlet var mainMenu: MenuWindow!

	// Globals
	weak var refreshTimer: NSTimer?
	var lastSuccessfulRefresh: NSDate?
	var lastRepoCheck = NSDate.distantPast() as NSDate
	var preferencesDirty: Bool = false
	var isRefreshing: Bool = false
	var isManuallyScrolling: Bool = false
	var ignoreNextFocusLoss: Bool = false
	var scrollBarWidth: CGFloat = 0.0
	var pullRequestDelegate = PullRequestDelegate()
	var opening: Bool  = false

	private var globalKeyMonitor: AnyObject?
	private var localKeyMonitor: AnyObject?
	private var mouseIgnoreTimer: PopTimer!
	private var filterTimer: PopTimer!
	private var messageView: NSView?

	func applicationDidFinishLaunching(notification: NSNotification) {
		app = self

		mainMenu.backgroundColor = NSColor.whiteColor()
		setupSortMethodMenu()
		DataManager.postProcessAllPrs()

		filterTimer = PopTimer(timeInterval: 0.2, callback: {
			app.updateMenu()
			app.scrollToTop()
		})

		mouseIgnoreTimer = PopTimer(timeInterval: 0.4, callback: {
			app.isManuallyScrolling = false
		})

		mainMenu.prTable.setDataSource(pullRequestDelegate)
		mainMenu.prTable.setDelegate(pullRequestDelegate)

		updateScrollBarWidth() // also updates menu
		scrollToTop()
		mainMenu.updateVibrancy()
		startRateLimitHandling()

		NSUserNotificationCenter.defaultUserNotificationCenter().delegate = self

		let cav = "Version " + currentAppVersion
		versionNumber.stringValue = cav
		aboutVersion.stringValue = cav

		if ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext) {
			startRefresh()
		} else {
			preferencesSelected(nil)
		}

		NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("networkStateChanged"), name: kReachabilityChangedNotification, object: nil)
		NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("updateScrollBarWidth"), name: NSPreferredScrollerStyleDidChangeNotification, object: nil)
		NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("updateMenu"), name: DARK_MODE_CHANGED, object: nil)

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
		updateMenu()
		updateLabelOptions()
		api.successfulRefreshesSinceLastLabelCheck = 0
		if Settings.showLabels {
			for r in DataItem.allItemsOfType("Repo", inMoc: mainObjectContext) as [Repo] {
				r.dirty = true
				r.lastDirtied = NSDate.distantPast() as? NSDate
			}
			preferencesDirty = true
		}
	}

	@IBAction func dontConfirmRemoveAllMergedSelected(sender: NSButton) {
		Settings.dontAskBeforeWipingMerged = (sender.integerValue==1)
	}

	@IBAction func hideAllPrsSection(sender: NSButton) {
		Settings.hideAllPrsSection = (sender.integerValue==1)
		DataManager.postProcessAllPrs()
		updateMenu()
	}

	@IBAction func markUnmergeableOnUserSectionsOnlySelected(sender: NSButton) {
		Settings.markUnmergeableOnUserSectionsOnly = (sender.integerValue==1)
		updateMenu()
	}

	@IBAction func displayRepositoryNameSelected(sender: NSButton) {
		Settings.showReposInName = (sender.integerValue==1)
		updateMenu()
	}

	@IBAction func useVibrancySelected(sender: NSButton) {
		Settings.useVibrancy = (sender.integerValue==1)
		NSNotificationCenter.defaultCenter().postNotificationName(UPDATE_VIBRANCY_NOTIFICATION, object: nil)
	}

	@IBAction func logActivityToConsoleSelected(sender: NSButton) {
		Settings.logActivityToConsole = (sender.integerValue==1)
		if Settings.logActivityToConsole {
			let alert = NSAlert()
			alert.messageText = "Warning"
			alert.informativeText = "Logging is a feature meant for error reporting, having it constantly enabled will cause this app to be less responsive and use more power"
			alert.addButtonWithTitle("OK")
			alert.runModal()
		}
	}

	@IBAction func includeLabelsInFilteringSelected(sender: NSButton) {
		Settings.includeLabelsInFilter = (sender.integerValue==1)
	}

	@IBAction func includeRepositoriesInfilterSelected(sender: NSButton) {
		Settings.includeReposInFilter = (sender.integerValue==1)
	}

	@IBAction func dontConfirmRemoveAllClosedSelected(sender: NSButton) {
		Settings.dontAskBeforeWipingClosed = (sender.integerValue==1)
	}

	@IBAction func autoParticipateOnMentionSelected(sender: NSButton) {
		Settings.autoParticipateInMentions = (sender.integerValue==1)
		DataManager.postProcessAllPrs()
		updateMenu()
	}

	@IBAction func dontKeepMyPrsSelected(sender: NSButton) {
		Settings.dontKeepPrsMergedByMe = (sender.integerValue==1)
	}

	@IBAction func hideAvatarsSelected(sender: NSButton) {
		Settings.hideAvatars = (sender.integerValue==1)
		DataManager.postProcessAllPrs()
		updateMenu()
	}

	@IBAction func hidePrsSelected(sender: NSButton) {
		Settings.shouldHideUncommentedRequests = (sender.integerValue==1)
		DataManager.postProcessAllPrs()
		updateMenu()
	}

	@IBAction func showAllCommentsSelected(sender: NSButton) {
		Settings.showCommentsEverywhere = (sender.integerValue==1);
		DataManager.postProcessAllPrs()
		updateMenu()
	}

	@IBAction func sortOrderSelected(sender: NSButton) {
		Settings.sortDescending = (sender.integerValue==1)
		setupSortMethodMenu()
		DataManager.postProcessAllPrs()
		updateMenu()
	}

	@IBAction func countOnlyListedPrsSelected(sender: NSButton) {
		Settings.countOnlyListedPrs = (sender.integerValue==1)
		DataManager.postProcessAllPrs()
		updateMenu()
	}

	@IBAction func hideNewRespositoriesSelected(sender: NSButton) {
		Settings.hideNewRepositories = (sender.integerValue==1)
	}

	@IBAction func openPrAtFirstUnreadCommentSelected(sender: NSButton) {
		Settings.openPrAtFirstUnreadComment = (sender.integerValue==1)
	}

	@IBAction func sortMethodChanged(sender: AnyObject) {
		Settings.sortMethod = sortModeSelect.indexOfSelectedItem
		DataManager.postProcessAllPrs()
		updateMenu()
	}

	@IBAction func showStatusItemsSelected(sender: NSButton) {
		Settings.showStatusItems = (sender.integerValue==1)
		updateMenu()
		updateStatusItemsOptions()

		api.successfulRefreshesSinceLastStatusCheck = 0
		if Settings.showStatusItems {
			for r in DataItem.allItemsOfType("Repo", inMoc: mainObjectContext) as [Repo] {
				r.dirty = true
				r.lastDirtied = NSDate.distantPast() as? NSDate
			}
			preferencesDirty = true
		}
	}

	private func updateStatusItemsOptions() {
		let enable = Settings.showStatusItems
		makeStatusItemsSelectable.enabled = enable
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
		updateMenu()
	}

	@IBAction func showCreationSelected(sender: NSButton) {
		Settings.showCreatedInsteadOfUpdated = (sender.integerValue==1)
		DataManager.postProcessAllPrs()
		updateMenu()
	}

	@IBAction func groupbyRepoSelected(sender: NSButton) {
		Settings.groupByRepo = (sender.integerValue==1)
		updateMenu()
	}

	@IBAction func moveAssignedPrsToMySectionSelected(sender: NSButton) {
		Settings.moveAssignedPrsToMySection = (sender.integerValue==1)
		DataManager.postProcessAllPrs()
		updateMenu()
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

	@IBAction func aboutLinkSelected(sender: NSButton) {
		NSWorkspace.sharedWorkspace().openURL(NSURL(string: "https://github.com/ptsochantaris/trailer")!)
	}

	func userNotificationCenter(center: NSUserNotificationCenter, shouldPresentNotification notification: NSUserNotification) -> Bool {
		return true
	}

	func userNotificationCenter(center: NSUserNotificationCenter, didActivateNotification notification: NSUserNotification) {
		switch notification.activationType {
		case NSUserNotificationActivationType.ActionButtonClicked: fallthrough
		case NSUserNotificationActivationType.ContentsClicked:
			NSUserNotificationCenter.defaultUserNotificationCenter().removeDeliveredNotification(notification)
			var urlToOpen = notification.userInfo?[NOTIFICATION_URL_KEY] as String?
			if urlToOpen == nil {
				var itemId = DataManager.idForUriPath(notification.userInfo?[PULL_REQUEST_ID_KEY] as String?)
				var pullRequest: PullRequest?
				if itemId != nil { // it's a pull request
					pullRequest = mainObjectContext.existingObjectWithID(itemId!, error: nil) as PullRequest?
					urlToOpen = pullRequest?.webUrl
				} else { // it's a comment
					itemId = DataManager.idForUriPath(notification.userInfo?[COMMENT_ID_KEY] as String?)
					if let c = mainObjectContext.existingObjectWithID(itemId!, error: nil) as? PRComment {
						urlToOpen = c.webUrl
						pullRequest = c.pullRequest
					}
				}
				pullRequest?.catchUpWithComments()
			}
			NSWorkspace.sharedWorkspace().openURL(NSURL(string: urlToOpen!)!)
			updateMenu()
		default: break
		}
	}

	func postNotificationOfType(type: PRNotificationType, forItem: DataItem) {
		if preferencesDirty {
			return
		}

		let notification = NSUserNotification()
		notification.userInfo = DataManager.infoForType(type, item: forItem)

		switch type {
		case .NewMention:
			let c = forItem as PRComment
			notification.title = "@" + (c.userName ?? "NoUserName") + " mentioned you:"
			notification.informativeText = c.body
			notification.subtitle = c.pullRequest.title
		case .NewComment:
			let c = forItem as PRComment
			notification.title = "@" + (c.userName ?? "NoUserName") + " commented:"
			notification.informativeText = c.body
			notification.subtitle = c.pullRequest.title
		case .NewPr:
			notification.title = "New PR"
			notification.subtitle = (forItem as PullRequest).title
		case .PrReopened:
			notification.title = "Re-Opened PR"
			notification.subtitle = (forItem as PullRequest).title
		case .PrMerged:
			notification.title = "PR Merged!"
			notification.subtitle = (forItem as PullRequest).title
		case .PrClosed:
			notification.title = "PR Closed"
			notification.subtitle = (forItem as PullRequest).title
		case .NewRepoSubscribed:
			notification.title = "New Repository Subscribed"
			notification.subtitle = (forItem as Repo).fullName
		case .NewRepoAnnouncement:
			notification.title = "New Repository"
			notification.subtitle = (forItem as Repo).fullName
		case .NewPrAssigned:
			notification.title = "PR Assigned"
			notification.subtitle = (forItem as PullRequest).title
		}

		if (type == .NewComment || type == .NewMention) && !Settings.hideAvatars && notification.respondsToSelector(Selector("setContentImage:")) { // let's add an avatar on this!
			if let url = (forItem as PRComment).avatarUrl {
				api.haveCachedAvatar(url, tryLoadAndCallback: { (image) in
					notification.contentImage = image
					NSUserNotificationCenter.defaultUserNotificationCenter().deliverNotification(notification)
				})
			}
		} else { // proceed as normal
			NSUserNotificationCenter.defaultUserNotificationCenter().deliverNotification(notification)
		}
	}

	func prItemSelected(pullRequest: PullRequest, alternativeSelect: Bool) {
		mainMenu.filter.becomeFirstResponder()
		ignoreNextFocusLoss = alternativeSelect

		if let url = pullRequest.urlForOpening() {
			NSWorkspace.sharedWorkspace().openURL(NSURL(string: url)!)
		}
		pullRequest.catchUpWithComments()

		let reSelectIndex = alternativeSelect ? mainMenu.prTable.selectedRow : -1

		updateMenu()

		if reSelectIndex > -1 && reSelectIndex < mainMenu.prTable.numberOfRows {
			mainMenu.prTable.selectRowIndexes(NSIndexSet(index: reSelectIndex), byExtendingSelection: false)
		}
	}

	func statusItemTapped() {
		let v = statusItem.view! as StatusItemView
		if v.highlighted {
			closeMenu()
		} else {
			v.highlighted = true
			sizeMenuAndShow(true)
		}
	}

	func menuWillOpen(menu: NSMenu) {
		if menu.title == "Options" {
			if !isRefreshing {
				refreshNow.title = " Refresh - " + api.lastUpdateDescription()
			}
		}
	}

	private func sizeMenuAndShow(show: Bool) {
		let screen = NSScreen.mainScreen()!
		let rightSide = screen.visibleFrame.origin.x + screen.visibleFrame.size.width
		let siv = statusItem.view! as StatusItemView
		var menuLeft = siv.window!.frame.origin.x
		let overflow = (menuLeft+MENU_WIDTH)-rightSide
		if overflow>0 {
			menuLeft -= overflow
		}

		var menuHeight = TOP_HEADER_HEIGHT
		let rowCount = mainMenu.prTable.numberOfRows
		let screenHeight = screen.visibleFrame.size.height
		if rowCount==0 {
			menuHeight += 95
		} else {
			menuHeight += 10
			for f in 0..<rowCount {
				let rowView = mainMenu.prTable.viewAtColumn(0, row: f, makeIfNecessary: true) as NSView
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

		mainMenu.setFrame(CGRectMake(menuLeft, bottom, MENU_WIDTH, menuHeight), display: false, animate: false)

		if show {
			mainMenu.prTable.deselectAll(nil)
			displayMenu()
		}
	}

	private func displayMenu() {
		opening = true
		mainMenu.level = Int(CGWindowLevelForKey(CGWindowLevelKey(kCGFloatingWindowLevelKey)))
		mainMenu.makeKeyAndOrderFront(self)
		NSApp.activateIgnoringOtherApps(true)
		opening = false
	}

	private func closeMenu() {
		let siv = statusItem.view as StatusItemView
		siv.highlighted = false
		mainMenu.orderOut(nil)
		mainMenu.prTable.deselectAll(nil)
	}

	func sectionHeaderRemoveSelected(headerTitle: NSString) {
		if headerTitle == kPullRequestSectionNames[PullRequestSection.Merged.rawValue] as String {
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
		} else if headerTitle == kPullRequestSectionNames[PullRequestSection.Closed.rawValue] as String {
			if Settings.dontAskBeforeWipingClosed {
				removeAllClosedRequests()
			} else {
				let closedRequests = PullRequest.allClosedRequestsInMoc(mainObjectContext)

				let alert = NSAlert()
				alert.messageText = "Clear \(closedRequests.count) closed PRs?"
				alert.informativeText = "This will clear \(closedRequests.count) closed PRs from your list.  This action cannot be undone, are you sure?"
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
		if !mainMenu.visible {
			statusItemTapped()
		}
	}

	private func removeAllMergedRequests() {
		for r in PullRequest.allMergedRequestsInMoc(mainObjectContext) {
			mainObjectContext.deleteObject(r)
		}
		DataManager.saveDB()
		updateMenu()
	}

	private func removeAllClosedRequests() {
		for r in PullRequest.allClosedRequestsInMoc(mainObjectContext) {
			mainObjectContext.deleteObject(r)
		}
		DataManager.saveDB()
		updateMenu()
	}

	func unPinSelectedFor(pullRequest: PullRequest) {
		mainObjectContext.deleteObject(pullRequest)
		DataManager.saveDB()
		updateMenu()
	}

	private func startRateLimitHandling() {
		NSNotificationCenter.defaultCenter().addObserver(serverList, selector: Selector("reloadData"), name: API_USAGE_UPDATE, object: nil)
		api.updateLimitsFromServer()
	}

	@IBAction func refreshReposSelected(sender: NSButton?) {
		prepareForRefresh()
		controlTextDidChange(nil)

		let tempContext = DataManager.tempContext()
		api.fetchRepositoriesToMoc(tempContext, andCallback: {

			if ApiServer.shouldReportRefreshFailureInMoc(tempContext) {
				var errorServers = [String]()
				for apiServer in ApiServer.allApiServersInMoc(tempContext) {
					if apiServer.goodToGo() && !(apiServer.lastSyncSucceeded?.boolValue ?? false) {
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
			self.completeRefresh()
		})
	}

	private func selectedServer() -> ApiServer? {
		let selected = serverList.selectedRow
		if selected >= 0 {
			return ApiServer.allApiServersInMoc(mainObjectContext)[selected]
		}
		return nil
	}

	private func indexOfObject(array: [AnyObject], _ value: AnyObject) -> Int? {
		for (index, elem) in enumerate(array) {
			if elem === value {
				return index
			}
		}
		return nil
	}

	@IBAction func deleteSelectedServerSelected(sender: NSButton) {
		if let selectedServer = selectedServer() {
			if let index = indexOfObject(ApiServer.allApiServersInMoc(mainObjectContext), selectedServer) {
				mainObjectContext.deleteObject(selectedServer)
				serverList.reloadData()
				serverList.selectRowIndexes(NSIndexSet(index: min(index, serverList.numberOfRows-1)), byExtendingSelection: false)
				fillServerApiFormFromSelectedServer()
				updateMenu()
				DataManager.saveDB()
			}
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
			} else if obj===mainMenu.filter {
				filterTimer.push()
			} else if obj===statusTermsField {
				let existingTokens = Settings.statusFilteringTerms
				let newTokens = statusTermsField.objectValue as [String]
				if existingTokens != newTokens {
					Settings.statusFilteringTerms = newTokens
					updateMenu()
				}
			} else if obj===commentAuthorBlacklist {
				let existingTokens = Settings.commentAuthorBlacklist
				let newTokens = commentAuthorBlacklist.objectValue as [String]
				if existingTokens != newTokens {
					Settings.commentAuthorBlacklist = newTokens
				}
			}
		}
	}

	private func reset() {
		preferencesDirty = true
		api.successfulRefreshesSinceLastStatusCheck = 0
		api.successfulRefreshesSinceLastLabelCheck = 0
		lastSuccessfulRefresh = nil
		lastRepoCheck = NSDate.distantPast() as NSDate
		projectsTable.reloadData()
		refreshButton.enabled = ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext)
		updateMenu()
	}

	@IBAction func markAllReadSelected(sender: NSMenuItem) {
		let f = PullRequest.requestForPullRequestsWithFilter(mainMenu.filter.stringValue)
		for r in mainObjectContext.executeFetchRequest(f, error: nil) as [PullRequest] {
			r.catchUpWithComments()
		}
		updateMenu()
	}

	@IBAction func preferencesSelected(sender: NSMenuItem?) {
		refreshTimer?.invalidate()
		refreshTimer = nil

		serverList.selectRowIndexes(NSIndexSet(index: 0), byExtendingSelection: false)

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
		dontConfirmRemoveAllMerged.integerValue = Settings.dontAskBeforeWipingMerged ? 1 : 0
		hideUncommentedPrs.integerValue = Settings.shouldHideUncommentedRequests ? 1 : 0
		autoParticipateWhenMentioned.integerValue = Settings.autoParticipateInMentions ? 1 : 0
		hideAvatars.integerValue = Settings.hideAvatars ? 1 : 0
		dontKeepPrsMergedByMe.integerValue = Settings.dontKeepPrsMergedByMe ? 1 : 0
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

		preferencesWindow.level = Int(CGWindowLevelForKey(CGWindowLevelKey(kCGFloatingWindowLevelKey)))
		preferencesWindow.makeKeyAndOrderFront(self)
	}

	private func colorButton(button: NSButton, withColor: NSColor) {
		let title = button.attributedTitle.mutableCopy() as NSMutableAttributedString
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
			r.dirty = true
			r.lastDirtied = NSDate()
		}
		preferencesDirty = true
		projectsTable.reloadData()
	}

	@IBAction func hideAllRepositoriesSelected(sender: NSButton) {
		for r in Repo.reposForFilter(repoFilter.stringValue) {
			r.hidden = true
			r.dirty = false
		}
		preferencesDirty = true
		projectsTable.reloadData()
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
		if apiServerWebPath.stringValue.lengthOfBytesUsingEncoding(NSUTF8StringEncoding)==0 {
			reportNeedFrontEnd()
		} else {
			let address = apiServerWebPath.stringValue + "/settings/tokens/new"
			NSWorkspace.sharedWorkspace().openURL(NSURL(string: address)!)
		}
	}

	@IBAction func viewExistingTokensSelected(sender: NSButton) {
		if apiServerWebPath.stringValue.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) == 0 {
			reportNeedFrontEnd()
		} else {
			let address = apiServerWebPath.stringValue + "/settings/applications"
			NSWorkspace.sharedWorkspace().openURL(NSURL(string: address)!)
		}
	}

	@IBAction func viewWatchlistSelected(sender: NSButton) {
		if apiServerWebPath.stringValue.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) == 0 {
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
		let parentCount = DataManager.countParentRepos(repoFilter.stringValue)
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

	func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
		let cell = tableColumn!.dataCellForRow(row) as NSCell

		if tableView === projectsTable {
			if tableColumn?.identifier == "hide" {
				if self.tableView(tableView, isGroupRow:row) {
					(cell as NSButtonCell).imagePosition = NSCellImagePosition.NoImage
					cell.state = NSMixedState
					cell.enabled = false
				} else {
					(cell as NSButtonCell).imagePosition = NSCellImagePosition.ImageOnly
					let r = repoForRow(row)
					if r.hidden.boolValue {
						cell.state = NSOnState
					} else {
						cell.state = NSOffState
					}
					cell.enabled = true
				}
			} else {
				if self.tableView(tableView, isGroupRow:row) {
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
				let c = cell as NSLevelIndicatorCell
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
			return (row == 0 || row == DataManager.countParentRepos(repoFilter.stringValue) + 1)
		} else {
			return false
		}
	}

	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		if tableView === projectsTable {
			return Repo.reposForFilter(repoFilter.stringValue).count + 2
		} else if tableView === mainMenu.prTable {
			let f = PullRequest.requestForPullRequestsWithFilter(mainMenu.filter.stringValue)
			return mainObjectContext.countForFetchRequest(f, error: nil)
		} else {
			return ApiServer.countApiServersInMoc(mainObjectContext)
		}
	}

	func tableView(tableView: NSTableView, setObjectValue object: AnyObject?, forTableColumn tableColumn: NSTableColumn?, row: Int) {
		if tableView === projectsTable {
			if !self.tableView(tableView, isGroupRow: row) {
				let r = repoForRow(row)
				let hideNow = object?.boolValue ?? false
				r.hidden = hideNow
				r.dirty = !hideNow
			}
			DataManager.saveDB()
			preferencesDirty = true
		}
	}

	func applicationShouldTerminate(sender: NSApplication) -> NSApplicationTerminateReply {
		DataManager.saveDB()
		return NSApplicationTerminateReply.TerminateNow
	}

	private func scrollToTop() {
		mainMenu.prTable.scrollToBeginningOfDocument(nil)
	}

	func windowDidBecomeKey(notification: NSNotification) {
		if notification.object === mainMenu {
			if ignoreNextFocusLoss {
				ignoreNextFocusLoss = false
			} else {
				scrollToTop()
				mainMenu.prTable.deselectAll(nil)
			}
			mainMenu.filter.becomeFirstResponder()
		}
	}

	func windowDidResignKey(notification: NSNotification) {
		if ignoreNextFocusLoss {
			displayMenu()
			return
		}
		if !opening {
			if notification.object === mainMenu {
				closeMenu()
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

	func networkStateChanged() {
		if api.reachability.currentReachabilityStatus() != NetworkStatus.NotReachable {
			DLog("Network is back")
			startRefreshIfItIsDue()
		}
	}

	private func startRefreshIfItIsDue() {
		if let l = lastSuccessfulRefresh {
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

	@IBAction func refreshNowSelected(sender: NSMenuItem) {
		if Repo.countVisibleReposInMoc(mainObjectContext) == 0 {
			preferencesSelected(nil)
			return
		}
		startRefresh()
	}

	private func checkApiUsage() {
		for apiServer in ApiServer.allApiServersInMoc(mainObjectContext) {
			if apiServer.requestsLimit?.doubleValue > 0 {
				if apiServer.requestsRemaining?.doubleValue == 0 {
					let apiLabel = apiServer.label ?? "NoApiServerLabel"
					let dateFormatter = NSDateFormatter()
					dateFormatter.doesRelativeDateFormatting = true
					dateFormatter.dateStyle = NSDateFormatterStyle.MediumStyle
					dateFormatter.dateStyle = NSDateFormatterStyle.MediumStyle
					let resetDateString = apiServer.resetDate == nil ? "(unspecified date)" : dateFormatter.stringFromDate(apiServer.resetDate!)

					let alert = NSAlert()
					alert.messageText = "Your API request usage for '\(apiLabel)' is over the limit!"
					alert.informativeText = "Your request cannot be completed until your hourly API allowance is reset at \(resetDateString).\n\nIf you get this error often, try to make fewer manual refreshes or reducing the number of repos you are monitoring.\n\nYou can check your API usage at any time from 'Servers' preferences pane at any time."
					alert.addButtonWithTitle("OK")
					alert.runModal()
				} else if(( (apiServer.requestsRemaining?.doubleValue ?? 0.0) / (apiServer.requestsLimit?.doubleValue ?? 1.0) ) < Double(LOW_API_WARNING)) {
					let apiLabel = apiServer.label ?? "NoApiServerLabel"
					let dateFormatter = NSDateFormatter()
					dateFormatter.doesRelativeDateFormatting = true
					dateFormatter.dateStyle = NSDateFormatterStyle.MediumStyle
					dateFormatter.dateStyle = NSDateFormatterStyle.MediumStyle
					let resetDateString = apiServer.resetDate == nil ? "(unspecified date)" : dateFormatter.stringFromDate(apiServer.resetDate!)

					let alert = NSAlert()
					alert.messageText = "Your API request usage for '\(apiLabel)' is close to full"
					alert.informativeText = "Try to make fewer manual refreshes, increasing the automatic refresh time, or reducing the number of repos you are monitoring.\n\nYour allowance will be reset by Github on \(resetDateString).\n\nYou can check your API usage from the 'Servers' preferences pane at any time."
					alert.addButtonWithTitle("OK")
					alert.runModal()
				}
			}
		}
	}

	func tabView(tabView: NSTabView, willSelectTabViewItem tabViewItem: NSTabViewItem?) {
		if tabView.indexOfTabViewItem(tabViewItem!) == 1 {
			if (lastRepoCheck.isEqualToDate(NSDate.distantPast() as NSDate) || Repo.countVisibleReposInMoc(mainObjectContext) == 0) && ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext) {
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
		(statusItem.view as StatusItemView).grayOut = true

		api.expireOldImageCacheEntries()
		DataManager.postMigrationTasks()

		isRefreshing = true

		if messageView != nil {
			updateMenu()
		}

		refreshNow.title = " Refreshing..."

		DLog("Starting refresh")
	}

	private func completeRefresh() {
		isRefreshing = false
		refreshButton.enabled = true
		projectsTable.enabled = true
		activityDisplay.stopAnimation(nil)
		DataManager.saveDB()
		projectsTable.reloadData()
		updateMenu()
		checkApiUsage()
		DataManager.saveDB()
		DataManager.sendNotifications()
		DLog("Refresh done")
	}

	private func startRefresh() {
		if isRefreshing {
		return
		}

		prepareForRefresh()

		let oldTarget: AnyObject? = refreshNow.target
		let oldAction = refreshNow.action
		refreshNow.action = nil
		refreshNow.target = nil

		api.fetchPullRequestsForActiveReposAndCallback {
			self.refreshNow.target = oldTarget
			self.refreshNow.action = oldAction
			if ApiServer.shouldReportRefreshFailureInMoc(mainObjectContext) {
				self.lastSuccessfulRefresh = NSDate()
				self.preferencesDirty = false
			}
			self.completeRefresh()
			self.refreshTimer = NSTimer.scheduledTimerWithTimeInterval(NSTimeInterval(Settings.refreshPeriod), target: self, selector: Selector("refreshTimerDone"), userInfo: nil, repeats: false)
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

	private func updateMenu() {
		var countString: String
		var attributes: Dictionary<String, AnyObject>
		if ApiServer.shouldReportRefreshFailureInMoc(mainObjectContext) {
			countString = "X"
			attributes = [ NSFontAttributeName: NSFont.boldSystemFontOfSize(10),
				NSForegroundColorAttributeName: MAKECOLOR(0.8, 0.0, 0.0, 1.0) ]
		} else {
			if Settings.countOnlyListedPrs {
				let f = PullRequest.requestForPullRequestsWithFilter(mainMenu.filter.stringValue)
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

		DLog("Updating menu, \(countString) total PRs")

		let width = countString.sizeWithAttributes(attributes).width

		let statusBar = NSStatusBar.systemStatusBar()
		let H = statusBar.thickness
		let length = H + width + STATUSITEM_PADDING*3
		if statusItem == nil {
			statusItem = statusBar.statusItemWithLength(-1) // should be NSVariableStatusItemLength but Swift can't compile this yet
		}

		let siv = StatusItemView(frame: CGRectMake(0, 0, length, H), label: countString, attributes: attributes)
		siv.highlighted = mainMenu.visible
		siv.grayOut = isRefreshing
		weak var weakSelf = self
		siv.tappedCallback = {
			weakSelf!.statusItemTapped()
		};
		statusItem.view = siv

		pullRequestDelegate.reloadData(mainMenu.filter.stringValue)
		mainMenu.prTable.reloadData()

		messageView?.removeFromSuperview()

		if mainMenu.prTable.numberOfRows == 0 {
			messageView = MessageView(frame: CGRectMake(0, 0, MENU_WIDTH, 100), message: DataManager.reasonForEmptyWithFilter(mainMenu.filter.stringValue))
			mainMenu.contentView.addSubview(messageView!)
		}

		sizeMenuAndShow(false)
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
		Settings.statusFilteringTerms = statusTermsField.objectValue as [String]
		updateStatusTermPreferenceControls()
	}

	@IBAction func testApiServerSelected(sender: NSButton) {
		sender.enabled = false
		let apiServer = selectedServer()!

		api.testApiToServer(apiServer, andCallback: { (error) in
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
		})
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
			apiServerTestButton.enabled = (apiServer.authToken?.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) > 0)
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
			apiServerTestButton.enabled = ((apiServer.authToken?.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) ?? 0) > 0)
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

	private func globalEvent(incomingEvent: NSEvent) {
		checkForHotkey(incomingEvent)
	}

	private func addHotKeySupport() {
		if(Settings.hotkeyEnable)
		{
			if globalKeyMonitor == nil {
				let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
				let options = [key: NSNumber(bool: (AXIsProcessTrusted() == 0))]
				if AXIsProcessTrustedWithOptions(options) != 0 {
					globalKeyMonitor = NSEvent.addGlobalMonitorForEventsMatchingMask(NSEventMask.KeyDownMask, handler: { (incomingEvent) in
						self.globalEvent(incomingEvent)
					})
				}
			}
		}
		else
		{
			if globalKeyMonitor != nil {
				NSEvent.removeMonitor(globalKeyMonitor!)
				globalKeyMonitor = nil
			}
		}

		if localKeyMonitor != nil {
			return
		}

		localKeyMonitor = NSEvent.addLocalMonitorForEventsMatchingMask(NSEventMask.KeyDownMask, handler: { (incomingEvent) -> NSEvent! in

			if self.checkForHotkey(incomingEvent) {
				return nil
			}

			if incomingEvent.window != self.mainMenu {
				return incomingEvent
			}

			switch incomingEvent.keyCode {
			case 125: // down
				if app.isManuallyScrolling && self.mainMenu.prTable.selectedRow == -1 {
					return nil
				}
				var i = self.mainMenu.prTable.selectedRow + 1
				if i < self.mainMenu.prTable.numberOfRows {
					while self.pullRequestDelegate.pullRequestAtRow(i) == nil {
						i++
					}
					self.scrollToIndex(i)
				}
				return nil
			case 126: // up
				if app.isManuallyScrolling && self.mainMenu.prTable.selectedRow == -1 {
					return nil
				}
				var i = self.mainMenu.prTable.selectedRow - 1
				if i > 0 {
					while self.pullRequestDelegate.pullRequestAtRow(i) == nil {
						i--
					}
					self.scrollToIndex(i)
				}
				return nil
			case 36: // enter
				let i = self.mainMenu.prTable.selectedRow
				if i >= 0 {
					if let v = self.mainMenu.prTable.rowViewAtRow(i, makeIfNecessary: false) as? PrItemView {
						let isAlternative = ((incomingEvent.modifierFlags & NSEventModifierFlags.AlternateKeyMask) == NSEventModifierFlags.AlternateKeyMask)
						self.prItemSelected(v.associatedPullRequest(), alternativeSelect: isAlternative)
					}
				}
				return nil
			case 53: // escape
				self.closeMenu()
				return nil
			default:
				break
			}

			return incomingEvent
		})
	}

	private func scrollToIndex(i: Int) {
		app.isManuallyScrolling = true
		mouseIgnoreTimer.push()
		mainMenu.prTable.scrollRowToVisible(i)
		dispatch_async(dispatch_get_main_queue(), {
			self.mainMenu.prTable.selectRowIndexes(NSIndexSet(index: i), byExtendingSelection: false)
		})
	}

	func focusedItemUrl() -> String? {
		let row = mainMenu.prTable.selectedRow
		var pr: PullRequest?
		if row >= 0 {
			mainMenu.prTable.deselectAll(nil)
			pr = pullRequestDelegate.pullRequestAtRow(row)
		}
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (Int64)(0.1 * Double(NSEC_PER_SEC))), dispatch_get_main_queue()) {
			self.mainMenu.prTable.selectRowIndexes(NSIndexSet(index: row), byExtendingSelection: false)
		}
		return pr?.webUrl
	}

	private func checkForHotkey(incomingEvent: NSEvent) -> Bool {
		var check = 0

		if Settings.hotkeyCommandModifier {
			if((incomingEvent.modifierFlags & NSEventModifierFlags.CommandKeyMask) == NSEventModifierFlags.CommandKeyMask) { check++ } else { check-- }
		} else {
			if((incomingEvent.modifierFlags & NSEventModifierFlags.CommandKeyMask) == NSEventModifierFlags.CommandKeyMask) { check-- } else { check++ }
		}

		if Settings.hotkeyControlModifier {
			if((incomingEvent.modifierFlags & NSEventModifierFlags.ControlKeyMask) == NSEventModifierFlags.ControlKeyMask) { check++ } else { check-- }
		} else {
			if((incomingEvent.modifierFlags & NSEventModifierFlags.ControlKeyMask) == NSEventModifierFlags.ControlKeyMask) { check-- } else { check++ }
		}

		if Settings.hotkeyOptionModifier {
			if((incomingEvent.modifierFlags & NSEventModifierFlags.AlternateKeyMask) == NSEventModifierFlags.AlternateKeyMask) { check++ } else { check-- }
		} else {
			if((incomingEvent.modifierFlags & NSEventModifierFlags.AlternateKeyMask) == NSEventModifierFlags.AlternateKeyMask) { check-- } else { check++ }
		}

		if Settings.hotkeyShiftModifier {
			if((incomingEvent.modifierFlags & NSEventModifierFlags.ShiftKeyMask) == NSEventModifierFlags.ShiftKeyMask) { check++ } else { check-- }
		} else {
			if((incomingEvent.modifierFlags & NSEventModifierFlags.ShiftKeyMask) == NSEventModifierFlags.ShiftKeyMask) { check-- } else { check++ }
		}

		if check==4 {
			let n = [
				"A": 0,
				"B": 11,
				"C": 8,
				"D": 2,
				"E": 14,
				"F": 3,
				"G": 5,
				"H": 4,
				"I": 34,
				"J": 38,
				"K": 40,
				"L": 37,
				"M": 46,
				"N": 45,
				"O": 31,
				"P": 35,
				"Q": 12,
				"R": 15,
				"S": 1,
				"T": 17,
				"U": 32,
				"V": 9,
				"W": 13,
				"X": 7,
				"Y": 16,
				"Z": 6 ][Settings.hotkeyLetter]

			if incomingEvent.keyCode==UInt16(n!) {
				statusItemTapped()
				return true
			}
		}
		return false
	}
	
	////////////// scrollbars
	
	private func updateScrollBarWidth() {
		if let s = mainMenu.scrollView.verticalScroller {
			if s.scrollerStyle == NSScrollerStyle.Legacy {
				scrollBarWidth = s.frame.size.width
			} else {
				scrollBarWidth = 0
			}
		}
		updateMenu()
	}
}
