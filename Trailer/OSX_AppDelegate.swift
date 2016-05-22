
var app: OSX_AppDelegate!

final class OSX_AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSUserNotificationCenterDelegate, NSOpenSavePanelDelegate {

	// Menus
	private static let prMenuController = NSWindowController(windowNibName:"MenuWindow")
	private let prMenu = prMenuController.window as! MenuWindow
	private static let issuesMenuController = NSWindowController(windowNibName:"MenuWindow")
	private let issuesMenu = issuesMenuController.window as! MenuWindow

	// Globals
	weak var refreshTimer: NSTimer?
	var openingWindow = false
	var isManuallyScrolling = false
	var ignoreNextFocusLoss = false
	var scrollBarWidth: CGFloat = 0.0
	var deferredUpdateTimer: PopTimer!

	private var systemSleeping = false
	private var globalKeyMonitor: AnyObject?
	private var localKeyMonitor: AnyObject?
	private var mouseIgnoreTimer: PopTimer!
	private var prFilterTimer: PopTimer!
	private var issuesFilterTimer: PopTimer!

	func applicationDidFinishLaunching(notification: NSNotification) {
		app = self

		setupDarkModeMonitoring()

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

		prMenu.itemDelegate = ItemDelegate(type: "PullRequest", sections: Section.prMenuTitles, removeButtonsInSections: [Section.Merged.prMenuName(), Section.Closed.prMenuName()])
		prMenu.delegate = self

		issuesMenu.itemDelegate = ItemDelegate(type: "Issue", sections: Section.issueMenuTitles, removeButtonsInSections: [Section.Closed.issuesMenuName()])
		issuesMenu.delegate = self

		updateScrollBarWidth() // also updates menu
		prMenu.scrollToTop()
		issuesMenu.scrollToTop()
		prMenu.updateVibrancy()
		issuesMenu.updateVibrancy()

		api.updateLimitsFromServer()

		let nc = NSUserNotificationCenter.defaultUserNotificationCenter()
		nc.delegate = self

		if ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext) {
			atNextEvent(self) { S in
				S.startRefresh()
			}
		} else if ApiServer.countApiServersInMoc(mainObjectContext) == 1, let a = ApiServer.allApiServersInMoc(mainObjectContext).first where a.authToken == nil || a.authToken!.isEmpty {
			startupAssistant()
		} else {
			preferencesSelected()
		}

		let n = NSNotificationCenter.defaultCenter()
		n.addObserver(self, selector: #selector(OSX_AppDelegate.updateScrollBarWidth), name: NSPreferredScrollerStyleDidChangeNotification, object: nil)

		addHotKeySupport()

		let s = SUUpdater.sharedUpdater()
		setUpdateCheckParameters()
		if !s.updateInProgress && Settings.checkForUpdatesAutomatically {
			s.checkForUpdatesInBackground()
		}

		let wn = NSWorkspace.sharedWorkspace().notificationCenter
		wn.addObserver(self, selector: #selector(OSX_AppDelegate.systemWillSleep), name: NSWorkspaceWillSleepNotification, object: nil)
		wn.addObserver(self, selector: #selector(OSX_AppDelegate.systemDidWake), name: NSWorkspaceDidWakeNotification, object: nil)

		// Unstick OS X notifications with custom actions but without an identifier, causes OS X to keep them forever
		if #available(OSX 10.10, *) {
			for notification in nc.deliveredNotifications {
				if notification.additionalActions != nil && notification.identifier == nil {
					nc.removeAllDeliveredNotifications()
					break
				}
			}
		}
	}

	func systemWillSleep() {
		systemSleeping = true
		DLog("System is going to sleep")
	}

	func systemDidWake() {
		DLog("System woke up")
		systemSleeping = false
		delay(1, self) { S in
			S.startRefreshIfItIsDue()
		}
	}

	func setUpdateCheckParameters() {
		let s = SUUpdater.sharedUpdater()
		let autoCheck = Settings.checkForUpdatesAutomatically
		s.automaticallyChecksForUpdates = autoCheck
		if autoCheck {
			s.updateCheckInterval = NSTimeInterval(3600)*NSTimeInterval(Settings.checkForUpdatesInterval)
		}
		DLog("Check for updates set to %@, every %f seconds", s.automaticallyChecksForUpdates ? "true" : "false", s.updateCheckInterval)
	}

	func userNotificationCenter(center: NSUserNotificationCenter, shouldPresentNotification notification: NSUserNotification) -> Bool {
		return false
	}

	func userNotificationCenter(center: NSUserNotificationCenter, didActivateNotification notification: NSUserNotification) {

		if let userInfo = notification.userInfo {

			func saveAndRefresh(i: ListableItem) {
				DataManager.saveDB()
				if i is PullRequest {
					updatePrMenu()
				} else if i is Issue {
					updateIssuesMenu()
				}
			}

			switch notification.activationType {
			case .AdditionalActionClicked:
				if #available(OSX 10.10, *) {
					if notification.additionalActivationAction?.identifier == "mute" {
						if let (_,i) = ListableItem.relatedItemsFromNotificationInfo(userInfo) {
							i.setMute(true)
							saveAndRefresh(i)
						}
						break
					} else if notification.additionalActivationAction?.identifier == "read" {
						if let (_,i) = ListableItem.relatedItemsFromNotificationInfo(userInfo) {
							i.catchUpWithComments()
							saveAndRefresh(i)
						}
						break
					}
				}
			case .ActionButtonClicked, .ContentsClicked:
				var urlToOpen = userInfo[NOTIFICATION_URL_KEY] as? String
				if urlToOpen == nil {
					if let (c,i) = ListableItem.relatedItemsFromNotificationInfo(userInfo) {
						urlToOpen = c?.webUrl ?? i.webUrl
						i.catchUpWithComments()
						saveAndRefresh(i)
					}
				}
				if let up = urlToOpen, u = NSURL(string: up) {
					NSWorkspace.sharedWorkspace().openURL(u)
				}
			default: break
			}
		}
		NSUserNotificationCenter.defaultUserNotificationCenter().removeDeliveredNotification(notification)
	}

	func postNotificationOfType(type: NotificationType, forItem: DataItem) {
		if preferencesDirty {
			return
		}

		let notification = NSUserNotification()
		notification.userInfo = DataManager.infoForType(type, item: forItem)

		switch type {
		case .NewMention:
			let c = forItem as! PRComment
			if c.parentShouldSkipNotifications { return }
			notification.title = "@" + S(c.userName) + " mentioned you:"
			notification.subtitle = c.notificationSubtitle
			notification.informativeText = c.body
			addPotentialExtraActions(notification)
		case .NewComment:
			let c = forItem as! PRComment
			if c.parentShouldSkipNotifications { return }
			notification.title = "@" + S(c.userName) + " commented:"
			notification.subtitle = c.notificationSubtitle
			notification.informativeText = c.body
			addPotentialExtraActions(notification)
		case .NewPr:
			let p = forItem as! PullRequest
			if p.shouldSkipNotifications { return }
			notification.title = "New PR"
			notification.subtitle = p.title
			addPotentialExtraActions(notification)
		case .PrReopened:
			let p = forItem as! PullRequest
			if p.shouldSkipNotifications { return }
			notification.title = "Re-Opened PR"
			notification.subtitle = p.title
			addPotentialExtraActions(notification)
		case .PrMerged:
			let p = forItem as! PullRequest
			if p.shouldSkipNotifications { return }
			notification.title = "PR Merged!"
			notification.subtitle = p.title
			addPotentialExtraActions(notification)
		case .PrClosed:
			let p = forItem as! PullRequest
			if p.shouldSkipNotifications { return }
			notification.title = "PR Closed"
			notification.subtitle = p.title
			addPotentialExtraActions(notification)
		case .NewRepoSubscribed:
			notification.title = "New Repository Subscribed"
			notification.subtitle = (forItem as! Repo).fullName
		case .NewRepoAnnouncement:
			notification.title = "New Repository"
			notification.subtitle = (forItem as! Repo).fullName
		case .NewPrAssigned:
			let p = forItem as! PullRequest
			if p.shouldSkipNotifications { return } // unmute on assignment option?
			notification.title = "PR Assigned"
			notification.subtitle = p.title
			addPotentialExtraActions(notification)
		case .NewStatus:
			let s = forItem as! PRStatus
			if s.parentShouldSkipNotifications { return }
			notification.title = "PR Status Update"
			notification.subtitle = s.pullRequest.title
			notification.informativeText = s.descriptionText
			addPotentialExtraActions(notification)
		case .NewIssue:
			let i = forItem as! Issue
			if i.shouldSkipNotifications { return }
			notification.title = "New Issue"
			notification.subtitle = i.title
			addPotentialExtraActions(notification)
		case .IssueReopened:
			let i = forItem as! Issue
			if i.shouldSkipNotifications { return }
			notification.title = "Re-Opened Issue"
			notification.subtitle = i.title
			addPotentialExtraActions(notification)
		case .IssueClosed:
			let i = forItem as! Issue
			if i.shouldSkipNotifications { return }
			notification.title = "Issue Closed"
			notification.subtitle = i.title
			addPotentialExtraActions(notification)
		case .NewIssueAssigned:
			let i = forItem as! Issue
			if i.shouldSkipNotifications { return }
			notification.title = "Issue Assigned"
			notification.subtitle = i.title
			addPotentialExtraActions(notification)
		}

		let t = S(notification.title)
		let s = S(notification.subtitle)
		let i = S(notification.informativeText)
		notification.identifier = "\(t) - \(s) - \(i)"

		let d = NSUserNotificationCenter.defaultUserNotificationCenter()
		if (type == .NewComment || type == .NewMention) && !Settings.hideAvatars {
			if let c = forItem as? PRComment, url = c.avatarUrl {
				api.haveCachedAvatar(url) { image, _ in
					notification.contentImage = image
					d.deliverNotification(notification)
				}
			}
		} else { // proceed as normal
			d.deliverNotification(notification)
		}
	}

	private func addPotentialExtraActions(n: NSUserNotification) {
		if #available(OSX 10.10, *) {
			n.additionalActions = [
				NSUserNotificationAction(identifier: "mute", title: "Mute this item"),
				NSUserNotificationAction(identifier: "read", title: "Mark this item as read")
			]
		}
	}

	func dataItemSelected(item: ListableItem, alternativeSelect: Bool) {

		ignoreNextFocusLoss = alternativeSelect

		let urlToOpen = item.urlForOpening()
		item.catchUpWithComments()

		let window: MenuWindow

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
		if !menu.visible {
			if menu === prMenu {
				issuesMenu.closeMenu()
			} else if menu === issuesMenu {
				prMenu.closeMenu()
			}
			menu.sizeAndShow(true)
		}
	}

	func sectionHeaderRemoveSelected(headerTitle: String) {

		let inMenu = visibleWindow()

		if inMenu === prMenu {
			if headerTitle == Section.Merged.prMenuName() {
				if Settings.dontAskBeforeWipingMerged {
					removeAllMergedRequests()
				} else {
					let mergedRequests = PullRequest.allMergedInMoc(mainObjectContext)

					let alert = NSAlert()
					alert.messageText = "Clear \(mergedRequests.count) merged PRs?"
					alert.informativeText = "This will clear \(mergedRequests.count) merged PRs from your list.  This action cannot be undone, are you sure?"
					alert.addButtonWithTitle("No")
					alert.addButtonWithTitle("Yes")
					alert.showsSuppressionButton = true

					if alert.runModal() == NSAlertSecondButtonReturn {
						removeAllMergedRequests()
						if alert.suppressionButton!.state == NSOnState {
							Settings.dontAskBeforeWipingMerged = true
						}
					}
				}
			} else if headerTitle == Section.Closed.prMenuName() {
				if Settings.dontAskBeforeWipingClosed {
					removeAllClosedRequests()
				} else {
					let closedRequests = PullRequest.allClosedInMoc(mainObjectContext)

					let alert = NSAlert()
					alert.messageText = "Clear \(closedRequests.count) closed PRs?"
					alert.informativeText = "This will remove \(closedRequests.count) closed PRs from your list.  This action cannot be undone, are you sure?"
					alert.addButtonWithTitle("No")
					alert.addButtonWithTitle("Yes")
					alert.showsSuppressionButton = true

					if alert.runModal() == NSAlertSecondButtonReturn {
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
		} else if inMenu === issuesMenu {
			if headerTitle == Section.Closed.issuesMenuName() {
				if Settings.dontAskBeforeWipingClosed {
					removeAllClosedIssues()
				} else {
					let closedIssues = Issue.allClosedInMoc(mainObjectContext)

					let alert = NSAlert()
					alert.messageText = "Clear \(closedIssues.count) closed issues?"
					alert.informativeText = "This will remove \(closedIssues.count) closed issues from your list.  This action cannot be undone, are you sure?"
					alert.addButtonWithTitle("No")
					alert.addButtonWithTitle("Yes")
					alert.showsSuppressionButton = true

					if alert.runModal() == NSAlertSecondButtonReturn {
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
		for r in PullRequest.allMergedInMoc(mainObjectContext) {
			mainObjectContext.deleteObject(r)
		}
		DataManager.saveDB()
		updatePrMenu()
	}

	private func removeAllClosedRequests() {
		for r in PullRequest.allClosedInMoc(mainObjectContext) {
			mainObjectContext.deleteObject(r)
		}
		DataManager.saveDB()
		updatePrMenu()
	}

	private func removeAllClosedIssues() {
		for i in Issue.allClosedInMoc(mainObjectContext) {
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

	override func controlTextDidChange(n: NSNotification) {
		if let obj = n.object as? NSSearchField {
			if obj === prMenu.filter {
				prFilterTimer.push()
			} else if obj === issuesMenu.filter {
				issuesFilterTimer.push()
			}
		}
	}

	func reset() {
		preferencesDirty = true
		api.resetAllStatusChecks()
		api.resetAllLabelChecks()
		Settings.lastSuccessfulRefresh = nil
		lastRepoCheck = never()
		preferencesWindow?.projectsTable.reloadData()
		deferredUpdateTimer.push()
	}

	func markAllReadSelectedFrom(window: MenuWindow) {
		if window == prMenu {
			let f = ListableItem.requestForItemsOfType("PullRequest", withFilter: prMenu.filter.stringValue, sectionIndex: -1)
			for r in try! mainObjectContext.executeFetchRequest(f) as! [PullRequest] {
				r.catchUpWithComments()
			}
			updatePrMenu()
		} else {
			let f = ListableItem.requestForItemsOfType("Issue", withFilter: issuesMenu.filter.stringValue, sectionIndex: -1)
			for i in try! mainObjectContext.executeFetchRequest(f) as! [Issue] {
				i.catchUpWithComments()
			}
			updateIssuesMenu()
		}
	}

	func preferencesSelected() {
		refreshTimer?.invalidate()
		refreshTimer = nil
		showPreferencesWindow(nil)
	}

	func application(sender: NSApplication, openFile filename: String) -> Bool {
		let url = NSURL(fileURLWithPath: filename)
		let ext = ((filename as NSString).lastPathComponent as NSString).pathExtension
		if ext == "trailerSettings" {
			DLog("Will open %@", url.absoluteString)
			tryLoadSettings(url, skipConfirm: Settings.dontConfirmSettingsImport)
			return true
		}
		return false
	}

	func tryLoadSettings(url: NSURL, skipConfirm: Bool) -> Bool {
		if appIsRefreshing {
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
			if alert.runModal() == NSAlertSecondButtonReturn {
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
		preferencesWindow?.reloadSettings()
		preferencesDirty = true
		startRefresh()

		return true
	}

	func applicationShouldTerminate(sender: NSApplication) -> NSApplicationTerminateReply {
		DataManager.saveDB()
		return .TerminateNow
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
			NSApp.activateIgnoringOtherApps(true)
		} else if !openingWindow {
			if notification.object === prMenu {
				prMenu.closeMenu()
			} else if notification.object === issuesMenu {
				issuesMenu.closeMenu()
			}
		}
	}
	
	func startRefreshIfItIsDue() {

		if let l = Settings.lastSuccessfulRefresh {
			let howLongAgo = NSDate().timeIntervalSinceDate(l)
			if fabs(howLongAgo) > NSTimeInterval(Settings.refreshPeriod) {
				startRefresh()
			} else {
				let howLongUntilNextSync = NSTimeInterval(Settings.refreshPeriod) - howLongAgo
				DLog("No need to refresh yet, will refresh in %f", howLongUntilNextSync)
				refreshTimer = NSTimer.scheduledTimerWithTimeInterval(howLongUntilNextSync, target: self, selector: #selector(OSX_AppDelegate.refreshTimerDone), userInfo: nil, repeats: false)
			}
		}
		else
		{
			startRefresh()
		}
	}

	private func checkApiUsage() {
		for apiServer in ApiServer.allApiServersInMoc(mainObjectContext) {
			if apiServer.goodToGo && apiServer.hasApiLimit, let resetDate = apiServer.resetDate {
				if apiServer.shouldReportOverTheApiLimit {
					let apiLabel = S(apiServer.label)
					let resetDateString = itemDateFormatter.stringFromDate(resetDate)

					let alert = NSAlert()
					alert.messageText = "Your API request usage for '\(apiLabel)' is over the limit!"
					alert.informativeText = "Your request cannot be completed until your hourly API allowance is reset \(resetDateString).\n\nIf you get this error often, try to make fewer manual refreshes or reducing the number of repos you are monitoring.\n\nYou can check your API usage at any time from 'Servers' preferences pane at any time."
					alert.addButtonWithTitle("OK")
					alert.runModal()
				} else if apiServer.shouldReportCloseToApiLimit {
					let apiLabel = S(apiServer.label)
					let resetDateString = itemDateFormatter.stringFromDate(resetDate)

					let alert = NSAlert()
					alert.messageText = "Your API request usage for '\(apiLabel)' is close to full"
					alert.informativeText = "Try to make fewer manual refreshes, increasing the automatic refresh time, or reducing the number of repos you are monitoring.\n\nYour allowance will be reset by GitHub \(resetDateString).\n\nYou can check your API usage from the 'Servers' preferences pane at any time."
					alert.addButtonWithTitle("OK")
					alert.runModal()
				}
			}
		}
	}

	func prepareForRefresh() {
		refreshTimer?.invalidate()
		refreshTimer = nil

		api.expireOldImageCacheEntries()
		DataManager.postMigrationTasks()

		appIsRefreshing = true
		preferencesWindow?.updateActivity()

		if prMenu.messageView != nil {
			updatePrMenu()
		}
		prMenu.refreshMenuItem.title = " Refreshing..."
		(prMenu.statusItem?.view as? StatusItemView)?.grayOut = Settings.grayOutWhenRefreshing

		if issuesMenu.messageView != nil {
			updateIssuesMenu()
		}
		issuesMenu.refreshMenuItem.title = " Refreshing..."
		(issuesMenu.statusItem?.view as? StatusItemView)?.grayOut = Settings.grayOutWhenRefreshing

		DLog("Starting refresh")
	}

	func completeRefresh() {
		appIsRefreshing = false
		preferencesDirty = false
		preferencesWindow?.updateActivity()
		DataManager.saveDB()
		preferencesWindow?.projectsTable.reloadData()
		checkApiUsage()
		DataManager.sendNotificationsIndexAndSave()
		DLog("Refresh done")
		updatePrMenu()
		updateIssuesMenu()
	}

	func startRefresh() {
		if appIsRefreshing {
			DLog("Won't start refresh because refresh is already ongoing")
			return
		}

		if systemSleeping {
			DLog("Won't start refresh because the system is in power-nap / sleep")
			return
		}

		if api.noNetworkConnection() {
			DLog("Won't start refresh because internet connectivity is down")
			return
		}

		if !ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext) {
			DLog("Won't start refresh because there are no configured API servers")
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
			if let s = self {
				s.prMenu.refreshMenuItem.target = oldPrTarget
				s.prMenu.refreshMenuItem.action = oldPrAction
				s.issuesMenu.refreshMenuItem.target = oldIssuesTarget
				s.issuesMenu.refreshMenuItem.action = oldIssuesAction

				if !ApiServer.shouldReportRefreshFailureInMoc(mainObjectContext) {
					Settings.lastSuccessfulRefresh = NSDate()
				}
				s.completeRefresh()
				s.refreshTimer = NSTimer.scheduledTimerWithTimeInterval(NSTimeInterval(Settings.refreshPeriod), target: s, selector: #selector(OSX_AppDelegate.refreshTimerDone), userInfo: nil, repeats: false)
			}
		}
	}

	func refreshTimerDone() {
		if ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext) && Repo.countVisibleReposInMoc(mainObjectContext) > 0 {
			if preferencesWindow != nil {
				preferencesDirty = true
			} else {
				startRefresh()
			}
		}
	}

	func updateIssuesMenu() {

		if Repo.interestedInIssues() {
			issuesMenu.showStatusItem()
		} else {
			issuesMenu.hideStatusItem()
			return
		}

		let countString: String
		let attributes: [String : AnyObject]
		if ApiServer.shouldReportRefreshFailureInMoc(mainObjectContext) {
			countString = "X"
			attributes = [ NSFontAttributeName: NSFont.boldSystemFontOfSize(10),
				NSForegroundColorAttributeName: MAKECOLOR(0.8, 0.0, 0.0, 1.0) ]
		} else {
            
            if Settings.countOnlyListedItems {
				let f = ListableItem.requestForItemsOfType("Issue", withFilter: issuesMenu.filter.stringValue, sectionIndex: -1)
                countString = String(mainObjectContext.countForFetchRequest(f, error: nil))
            } else {
                countString = String(Issue.countOpenInMoc(mainObjectContext))
            }

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
		let shouldGray = Settings.grayOutWhenRefreshing && appIsRefreshing

		if let s = issuesMenu.statusItem?.view as? StatusItemView where compareDict(s.textAttributes, to: attributes) && s.statusLabel == countString && s.grayOut == shouldGray {
			updateStatusItem = false
		}

		if updateStatusItem {
			atNextEvent(self) { S in
				DLog("Updating issues status item")
				let im = S.issuesMenu
				let siv = StatusItemView(frame: CGRectMake(0, 0, length+2, H), label: countString, prefix: "issues", attributes: attributes)
				siv.labelOffset = 2
				siv.highlighted = im.visible
				siv.grayOut = shouldGray
				siv.tappedCallback = { [weak S] in
					if let S = S {
						let m = S.issuesMenu
						if m.visible {
							m.closeMenu()
						} else {
							S.showMenu(m)
						}
					}
				}
				im.statusItem?.view = siv
			}
		}

		issuesMenu.reload()

		if issuesMenu.table.numberOfRows == 0 {
			let m = MessageView(frame: CGRectMake(0, 0, MENU_WIDTH, 100), message: Issue.reasonForEmptyWithFilter(issuesMenu.filter.stringValue))
			issuesMenu.messageView = m
			issuesMenu.contentView!.addSubview(m)
		}

		issuesMenu.sizeAndShow(false)
	}

	func updatePrMenu() {

		if Repo.interestedInPrs() || !Repo.interestedInIssues() {
			prMenu.showStatusItem()
		} else {
			prMenu.hideStatusItem()
			return
		}

		let countString: String
		let attributes: [String : AnyObject]
		if ApiServer.shouldReportRefreshFailureInMoc(mainObjectContext) {
			countString = "X"
			attributes = [ NSFontAttributeName: NSFont.boldSystemFontOfSize(10),
				NSForegroundColorAttributeName: MAKECOLOR(0.8, 0.0, 0.0, 1.0) ]
		} else {

			if Settings.countOnlyListedItems {
				let f = ListableItem.requestForItemsOfType("PullRequest", withFilter: prMenu.filter.stringValue, sectionIndex: -1)
				countString = String(mainObjectContext.countForFetchRequest(f, error: nil))
			} else {
				countString = String(PullRequest.countOpenInMoc(mainObjectContext))
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
        let shouldGray = Settings.grayOutWhenRefreshing && appIsRefreshing
		if let s = prMenu.statusItem?.view as? StatusItemView where compareDict(s.textAttributes, to: attributes) && s.statusLabel == countString && s.grayOut == shouldGray {
			updateStatusItem = false
		}

        if updateStatusItem {
			atNextEvent(self) { S in
				DLog("Updating PR status item")
				let pm = S.prMenu
				let siv = StatusItemView(frame: CGRectMake(0, 0, length, H), label: countString, prefix: "pr", attributes: attributes)
				siv.highlighted = pm.visible
				siv.grayOut = shouldGray
				siv.tappedCallback = { [weak S] in
					if let S = S {
						let m = S.prMenu
						if m.visible {
							m.closeMenu()
						} else {
							S.showMenu(m)
						}
					}
				}
				pm.statusItem?.view = siv
			}
        }

		prMenu.reload()

		if prMenu.table.numberOfRows == 0 {
			let m = MessageView(frame: CGRectMake(0, 0, MENU_WIDTH, 100), message: PullRequest.reasonForEmptyWithFilter(prMenu.filter.stringValue))
			prMenu.messageView = m
			prMenu.contentView!.addSubview(m)
		}

		prMenu.sizeAndShow(false)
	}

	private func compareDict(from: [String : AnyObject], to: [String : AnyObject]) -> Bool {
        for (key, value) in from {
            if let v = to[key] {
                if !v.isEqual(value) {
                    return false
                }
            } else {
                return false
            }
        }
        return true
    }

	/////////////////////// keyboard shortcuts

	func addHotKeySupport() {
		if Settings.hotkeyEnable {
			if globalKeyMonitor == nil {
				let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
				let options = [key: NSNumber(bool: (AXIsProcessTrusted() == false))]
				if AXIsProcessTrustedWithOptions(options) == true {
					globalKeyMonitor = NSEvent.addGlobalMonitorForEventsMatchingMask(NSEventMask.KeyDownMask) { [weak self] incomingEvent in
						self?.checkForHotkey(incomingEvent)
						return
					}
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

		localKeyMonitor = NSEvent.addLocalMonitorForEventsMatchingMask(NSEventMask.KeyDownMask) { [weak self] (incomingEvent) -> NSEvent? in

			guard let S = self else { return incomingEvent }

			if S.checkForHotkey(incomingEvent) ?? false {
				return nil
			}

			if let w = incomingEvent.window as? MenuWindow {
				//DLog("Keycode: %d", incomingEvent.keyCode)

				switch incomingEvent.keyCode {
				case 123, 124: // left, right
					if !(hasModifier(incomingEvent, .CommandKeyMask) && hasModifier(incomingEvent, .AlternateKeyMask)) {
						return incomingEvent
					}

					if app.isManuallyScrolling && w.table.selectedRow == -1 { return nil }

					if Repo.interestedInPrs() && Repo.interestedInIssues() {
						if w === S.prMenu {
							S.showMenu(S.issuesMenu)
						} else if w === S.issuesMenu {
							S.showMenu(S.prMenu)
						}
					}
					return nil
				case 125: // down
					if hasModifier(incomingEvent, .ShiftKeyMask) {
						return incomingEvent
					}
					if app.isManuallyScrolling && w.table.selectedRow == -1 { return nil }
					var i = w.table.selectedRow + 1
					if i < w.table.numberOfRows {
						while w.itemDelegate.itemAtRow(i) == nil { i += 1 }
						S.scrollToIndex(i, inMenu: w)
					}
					return nil
				case 126: // up
					if hasModifier(incomingEvent, .ShiftKeyMask) {
						return incomingEvent
					}
					if app.isManuallyScrolling && w.table.selectedRow == -1 { return nil }
					var i = w.table.selectedRow - 1
					if i > 0 {
						while w.itemDelegate.itemAtRow(i) == nil { i -= 1 }
						S.scrollToIndex(i, inMenu: w)
					}
					return nil
				case 36: // enter
					if let c = NSTextInputContext.currentInputContext() where c.client.hasMarkedText() {
						return incomingEvent
					}
					if app.isManuallyScrolling && w.table.selectedRow == -1 { return nil }
					if let dataItem = w.itemDelegate.itemAtRow(w.table.selectedRow) {
						let isAlternative = hasModifier(incomingEvent, .AlternateKeyMask)
						S.dataItemSelected(dataItem, alternativeSelect: isAlternative)
					}
					return nil
				case 53: // escape
					w.closeMenu()
					return nil
				default:
					break
				}
			}
			return incomingEvent
		}
	}

	private func scrollToIndex(i: Int, inMenu: MenuWindow) {
		app.isManuallyScrolling = true
		mouseIgnoreTimer.push()
		inMenu.table.scrollRowToVisible(i)
		atNextEvent {
			inMenu.table.selectRowIndexes(NSIndexSet(index: i), byExtendingSelection: false)
		}
	}

	func focusedItem() -> ListableItem? {
		if prMenu.visible {
			return prMenu.focusedItem()
		} else if issuesMenu.visible {
			return issuesMenu.focusedItem()
		} else {
			return nil
		}
	}

	private func checkForHotkey(incomingEvent: NSEvent) -> Bool {
		var check = 0

		let cmdPressed = hasModifier(incomingEvent, .CommandKeyMask)
		if Settings.hotkeyCommandModifier { check += cmdPressed ? 1 : -1 } else { check += cmdPressed ? -1 : 1 }

		let ctrlPressed = hasModifier(incomingEvent, .ControlKeyMask)
		if Settings.hotkeyControlModifier { check += ctrlPressed ? 1 : -1 } else { check += ctrlPressed ? -1 : 1 }

		let altPressed = hasModifier(incomingEvent, .AlternateKeyMask)
		if Settings.hotkeyOptionModifier { check += altPressed ? 1 : -1 } else { check += altPressed ? -1 : 1 }

		let shiftPressed = hasModifier(incomingEvent, .ShiftKeyMask)
		if Settings.hotkeyShiftModifier { check += shiftPressed ? 1 : -1 } else { check += shiftPressed ? -1 : 1 }

		let keyMap = [
			"A": 0, "B": 11, "C": 8, "D": 2, "E": 14, "F": 3, "G": 5, "H": 4, "I": 34, "J": 38,
			"K": 40, "L": 37, "M": 46, "N": 45, "O": 31, "P": 35, "Q": 12, "R": 15, "S": 1,
			"T": 17, "U": 32, "V": 9, "W": 13, "X": 7, "Y": 16, "Z": 6 ]

		if check==4, let n = keyMap[Settings.hotkeyLetter] where incomingEvent.keyCode == UInt16(n) {
			if Repo.interestedInPrs() {
				showMenu(prMenu)
			} else if Repo.interestedInIssues() {
				showMenu(issuesMenu)
			}
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
				w.level = Int(CGWindowLevelForKey(CGWindowLevelKey.FloatingWindowLevelKey))
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
			w.level = Int(CGWindowLevelForKey(CGWindowLevelKey.FloatingWindowLevelKey))
			w.version.stringValue = versionString()
			w.center()
			w.makeKeyAndOrderFront(self)
		}
	}
	func closedAboutWindow() {
		aboutWindowController = nil
	}

	private var preferencesWindowController: NSWindowController?
	private var preferencesWindow: PreferencesWindow?
	func showPreferencesWindow(selectTab: Int?) {
		if preferencesWindowController == nil {
			preferencesWindowController = NSWindowController(windowNibName:"PreferencesWindow")
		}
		if let w = preferencesWindowController!.window as? PreferencesWindow {
			w.level = Int(CGWindowLevelForKey(CGWindowLevelKey.FloatingWindowLevelKey))
			w.center()
			w.makeKeyAndOrderFront(self)
			preferencesWindow = w
			if let s = selectTab {
				w.tabs.selectTabViewItemAtIndex(s)
			}
		}
	}
	func closedPreferencesWindow() {
		preferencesWindow = nil
		preferencesWindowController = nil
	}

	func statusItemWithView(view: NSView) -> NSStatusItem? {
		if prMenu.statusItem?.view === view {
			return prMenu.statusItem
		}
		if issuesMenu.statusItem?.view === view {
			return issuesMenu.statusItem
		}
		return nil
	}

	func visibleWindow() -> MenuWindow? {
		if prMenu.visible { return prMenu }
		if issuesMenu.visible { return issuesMenu }
		return nil
	}

	func updateVibrancies() {
		prMenu.updateVibrancy()
		issuesMenu.updateVibrancy()
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
		atNextEvent(self) { S in
			if #available(OSX 10.10, *) {
				let c = NSAppearance.currentAppearance()
				if c.respondsToSelector(Selector("allowsVibrancy")) {
					S.darkMode = c.name.rangeOfString(NSAppearanceNameVibrantDark) != nil
					return
				}
			}
			S.darkMode = false
		}
	}

	private func setupDarkModeMonitoring() {
		NSDistributedNotificationCenter.defaultCenter().addObserver(self, selector: #selector(OSX_AppDelegate.checkDarkMode), name: "AppleInterfaceThemeChangedNotification", object: nil)
		checkDarkMode()
	}
}
