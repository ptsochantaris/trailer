
var app: OSX_AppDelegate!

final class OSX_AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSUserNotificationCenterDelegate, NSOpenSavePanelDelegate {

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
	var opening: Bool = false
	var systemSleeping = false

	private var globalKeyMonitor: AnyObject?
	private var localKeyMonitor: AnyObject?
	private var mouseIgnoreTimer: PopTimer!
	private var prFilterTimer: PopTimer!
	private var issuesFilterTimer: PopTimer!
	var deferredUpdateTimer: PopTimer!

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

		api.updateLimitsFromServer()

		let nc = NSUserNotificationCenter.defaultUserNotificationCenter()
		nc.delegate = self

		if ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext) {
			atNextEvent {
				self.startRefresh()
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
					break;
				}
			}
		}
	}

	func systemWillSleep() {
		systemSleeping = true
		DLog("System is going to sleep");
	}

	func systemDidWake() {
		DLog("System woke up");
		systemSleeping = false
		delay(1.0) { [weak self] in
			self?.startRefreshIfItIsDue()
		}
	}

	func setUpdateCheckParameters() {
		let s = SUUpdater.sharedUpdater()
		let autoCheck = Settings.checkForUpdatesAutomatically
		s.automaticallyChecksForUpdates = autoCheck
		if autoCheck {
			s.updateCheckInterval = NSTimeInterval(3600)*NSTimeInterval(Settings.checkForUpdatesInterval)
		}
		DLog("Check for updates set to %d every %f seconds", s.automaticallyChecksForUpdates, s.updateCheckInterval)
	}

	func userNotificationCenter(center: NSUserNotificationCenter, shouldPresentNotification notification: NSUserNotification) -> Bool {
		return false
	}

	func userNotificationCenter(center: NSUserNotificationCenter, didActivateNotification notification: NSUserNotification) {

		func relatedItems(userInfo: [String : AnyObject?]) -> (PRComment?, ListableItem)? {
			var item: ListableItem?
			var comment: PRComment?
			if let itemId = DataManager.idForUriPath(userInfo[COMMENT_ID_KEY] as? String), c = existingObjectWithID(itemId) as? PRComment {
				comment = c
				item = c.pullRequest ?? c.issue
			} else if let itemId = DataManager.idForUriPath(userInfo[PULL_REQUEST_ID_KEY] as? String) {
				item = existingObjectWithID(itemId) as? ListableItem
			} else if let itemId = DataManager.idForUriPath(userInfo[ISSUE_ID_KEY] as? String) {
				item = existingObjectWithID(itemId) as? ListableItem
			}
			if item == nil {
				return nil
			} else {
				return (comment, item!)
			}
		}

		if let userInfo = notification.userInfo {

			switch notification.activationType {
			case .AdditionalActionClicked:
				if #available(OSX 10.10, *) {
					if notification.additionalActivationAction?.identifier == "mute" {
						if let (_,i) = relatedItems(userInfo) {
							i.muted = true
							i.postProcess()
							DataManager.saveDB()
							if i is PullRequest {
								updatePrMenu()
							} else if i is Issue {
								updateIssuesMenu()
							}
						}
						break
					} else if notification.additionalActivationAction?.identifier == "read" {
						if let (_,i) = relatedItems(userInfo) {
							i.catchUpWithComments()
							DataManager.saveDB()
							if i is PullRequest {
								updatePrMenu()
							} else if i is Issue {
								updateIssuesMenu()
							}
						}
						break
					}
				}
			case .ActionButtonClicked: fallthrough
			case .ContentsClicked:
				var urlToOpen = userInfo[NOTIFICATION_URL_KEY] as? String
				if urlToOpen == nil {
					if let (c,i) = relatedItems(userInfo) {
						urlToOpen = c?.webUrl ?? i.webUrl
						i.catchUpWithComments()
						DataManager.saveDB()
						if i is PullRequest {
							updatePrMenu()
						} else if i is Issue {
							updateIssuesMenu()
						}
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

	func postNotificationOfType(type: PRNotificationType, forItem: DataItem) {
		if preferencesDirty {
			return
		}

		let notification = NSUserNotification()
		notification.userInfo = DataManager.infoForType(type, item: forItem)

		switch type {
		case .NewMention:
			let c = forItem as! PRComment
			if c.parentIsMuted() { return }
			notification.title = "@" + (c.userName ?? "NoUserName") + " mentioned you:"
			notification.subtitle = c.notificationSubtitle()
			notification.informativeText = c.body
			addPotentialExtraActions(notification)
		case .NewComment:
			let c = forItem as! PRComment
			if c.parentIsMuted() { return }
			notification.title = "@" + (c.userName ?? "NoUserName") + " commented:"
			notification.subtitle = c.notificationSubtitle()
			notification.informativeText = c.body
			addPotentialExtraActions(notification)
		case .NewPr:
			let p = forItem as! PullRequest
			if p.muted?.boolValue ?? false { return }
			notification.title = "New PR"
			notification.subtitle = p.title
			addPotentialExtraActions(notification)
		case .PrReopened:
			let p = forItem as! PullRequest
			if p.muted?.boolValue ?? false { return }
			notification.title = "Re-Opened PR"
			notification.subtitle = p.title
			addPotentialExtraActions(notification)
		case .PrMerged:
			let p = forItem as! PullRequest
			if p.muted?.boolValue ?? false { return }
			notification.title = "PR Merged!"
			notification.subtitle = p.title
			addPotentialExtraActions(notification)
		case .PrClosed:
			let p = forItem as! PullRequest
			if p.muted?.boolValue ?? false { return }
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
			if p.muted?.boolValue ?? false { return } // unmute on assignment option?
			notification.title = "PR Assigned"
			notification.subtitle = p.title
			addPotentialExtraActions(notification)
		case .NewStatus:
			let s = forItem as! PRStatus
			if s.parentIsMuted() { return }
			notification.title = "PR Status Update"
			notification.subtitle = s.pullRequest.title
			notification.informativeText = s.descriptionText
			addPotentialExtraActions(notification)
		case .NewIssue:
			let i = forItem as! Issue
			if i.muted?.boolValue ?? false { return }
			notification.title = "New Issue"
			notification.subtitle = i.title
			addPotentialExtraActions(notification)
		case .IssueReopened:
			let i = forItem as! Issue
			if i.muted?.boolValue ?? false { return }
			notification.title = "Re-Opened Issue"
			notification.subtitle = i.title
			addPotentialExtraActions(notification)
		case .IssueClosed:
			let i = forItem as! Issue
			if i.muted?.boolValue ?? false { return }
			notification.title = "Issue Closed"
			notification.subtitle = i.title
			addPotentialExtraActions(notification)
		case .NewIssueAssigned:
			let i = forItem as! Issue
			if i.muted?.boolValue ?? false { return }
			notification.title = "Issue Assigned"
			notification.subtitle = i.title
			addPotentialExtraActions(notification)
		}

		let t = notification.title ?? "notitle"
		let s = notification.subtitle ?? "nosub"
		let i = notification.informativeText ?? "noinfo"
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

			var screen: NSScreen?
			for s in NSScreen.screens() ?? [] {
				if CGRectContainsRect(s.frame, siv.window!.frame) {
					screen = s
					break;
				}
			}

			if(screen==nil) {
				return
			}

			var menuLeft = siv.window!.frame.origin.x
			let rightSide = screen!.visibleFrame.origin.x + screen!.visibleFrame.size.width
			let overflow = (menuLeft+MENU_WIDTH)-rightSide
			if overflow > 0 {
				menuLeft -= overflow
			}

			var menuHeight = TOP_HEADER_HEIGHT
			let rowCount = window.table.numberOfRows
			let screenHeight = screen!.visibleFrame.size.height
			if rowCount==0 {
				menuHeight += 95
			} else {
				menuHeight += 10
				for f in 0..<rowCount {
					let rowView = window.table.viewAtColumn(0, row: f, makeIfNecessary: true)!
					menuHeight += rowView.frame.size.height + 2
					if menuHeight >= screenHeight {
						break
					}
				}
			}

			var bottom = screen!.visibleFrame.origin.y
			if menuHeight < screenHeight {
				bottom += screenHeight-menuHeight
			} else {
				menuHeight = screenHeight
			}

			window.setFrame(CGRectMake(menuLeft, bottom, MENU_WIDTH, menuHeight), display: false, animate: false)

			if andShow {
				window.table.deselectAll(nil)
				opening = true
				window.level = Int(CGWindowLevelForKey(CGWindowLevelKey.FloatingWindowLevelKey))
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

	override func controlTextDidChange(n: NSNotification) {
		if let obj = n.object as? NSSearchField {
			if obj===prMenu.filter {
				prFilterTimer.push()
			} else if obj===issuesMenu.filter {
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
		showPreferencesWindow()
	}

	func application(sender: NSApplication, openFile filename: String) -> Bool {
		let url = NSURL(fileURLWithPath: filename)
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
		preferencesWindow?.reloadSettings()
		preferencesDirty = true
		startRefresh()

		return true
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

		(prMenu.statusItem?.view as? StatusItemView)?.grayOut = Settings.grayOutWhenRefreshing
		(issuesMenu.statusItem?.view as? StatusItemView)?.grayOut = Settings.grayOutWhenRefreshing

		api.expireOldImageCacheEntries()
		DataManager.postMigrationTasks()

		isRefreshing = true
		preferencesWindow?.updateActivity()

		if prMenu.messageView != nil {
			updatePrMenu()
		}

		if issuesMenu.messageView != nil {
			updateIssuesMenu()
		}

		setRefreshLabel(" Refreshing...")

		DLog("Starting refresh")
	}

	func completeRefresh() {
		isRefreshing = false
		preferencesDirty = false
		preferencesWindow?.updateActivity()
		DataManager.saveDB()
		preferencesWindow?.projectsTable.reloadData()
		updatePrMenu()
		updateIssuesMenu()
		checkApiUsage()
		DataManager.sendNotificationsIndexAndSave()
		DLog("Refresh done")
	}

	func startRefresh() {
		if isRefreshing {
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

		var countString: String
		var attributes: [String : AnyObject]
		if ApiServer.shouldReportRefreshFailureInMoc(mainObjectContext) {
			countString = "X"
			attributes = [ NSFontAttributeName: NSFont.boldSystemFontOfSize(10),
				NSForegroundColorAttributeName: MAKECOLOR(0.8, 0.0, 0.0, 1.0) ]
		} else {
            
            if Settings.countOnlyListedItems {
				let f = ListableItem.requestForItemsOfType("Issue", withFilter: issuesMenu.filter.stringValue, sectionIndex: -1)
                countString = String(mainObjectContext.countForFetchRequest(f, error: nil))
            } else {
                countString = String(Issue.countOpenIssuesInMoc(mainObjectContext))
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
		let shouldGray = Settings.grayOutWhenRefreshing && isRefreshing

		if let s = issuesMenu.statusItem?.view as? StatusItemView where compareDict(s.textAttributes, to: attributes) && s.statusLabel == countString && s.grayOut == shouldGray {
			updateStatusItem = false
		}

		if updateStatusItem {
			atNextEvent { [weak self] in
				DLog("Updating issues status item");
				if let im = self?.issuesMenu {
					let siv = StatusItemView(frame: CGRectMake(0, 0, length+2, H), label: countString, prefix: "issues", attributes: attributes)
					siv.labelOffset = 2
					siv.highlighted = im.visible
					siv.grayOut = shouldGray
					siv.tappedCallback = { [weak self] in
						if let m = self?.issuesMenu {
							if m.visible {
								self?.closeMenu(m)
							} else {
								self?.showMenu(m)
							}
						}
					}
					im.statusItem?.view = siv
				}
			}
		}

		issuesDelegate.reloadData(issuesMenu.filter.stringValue)
		issuesMenu.table.reloadData()

		issuesMenu.messageView?.removeFromSuperview()

		if issuesMenu.table.numberOfRows == 0 {
			let m = MessageView(frame: CGRectMake(0, 0, MENU_WIDTH, 100), message: DataManager.reasonForEmptyIssuesWithFilter(issuesMenu.filter.stringValue))
			issuesMenu.messageView = m
			issuesMenu.contentView!.addSubview(m)
		}

		sizeMenu(issuesMenu, andShow: false)
	}

	func updatePrMenu() {

		if Repo.interestedInPrs() || !Repo.interestedInIssues() {
			prMenu.showStatusItem()
		} else {
			prMenu.hideStatusItem()
			return
		}

		var countString: String
		var attributes: [String : AnyObject]
		if ApiServer.shouldReportRefreshFailureInMoc(mainObjectContext) {
			countString = "X"
			attributes = [ NSFontAttributeName: NSFont.boldSystemFontOfSize(10),
				NSForegroundColorAttributeName: MAKECOLOR(0.8, 0.0, 0.0, 1.0) ]
		} else {

			if Settings.countOnlyListedItems {
				let f = ListableItem.requestForItemsOfType("PullRequest", withFilter: prMenu.filter.stringValue, sectionIndex: -1)
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
			atNextEvent { [weak self] in
				DLog("Updating PR status item");
				if let pm = self?.prMenu {
					let siv = StatusItemView(frame: CGRectMake(0, 0, length, H), label: countString, prefix: "pr", attributes: attributes)
					siv.highlighted = pm.visible
					siv.grayOut = shouldGray
					siv.tappedCallback = { [weak self] in
						if let m = self?.prMenu {
							if m.visible {
								self?.closeMenu(m)
							} else {
								self?.showMenu(m)
							}
						}
					}
					pm.statusItem?.view = siv
				}
			}
        }

		pullRequestDelegate.reloadData(prMenu.filter.stringValue)
		prMenu.table.reloadData()

		prMenu.messageView?.removeFromSuperview()

		if prMenu.table.numberOfRows == 0 {
			let m = MessageView(frame: CGRectMake(0, 0, MENU_WIDTH, 100), message: DataManager.reasonForEmptyWithFilter(prMenu.filter.stringValue))
			prMenu.messageView = m
			prMenu.contentView!.addSubview(m)
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

		localKeyMonitor = NSEvent.addLocalMonitorForEventsMatchingMask(NSEventMask.KeyDownMask) { [weak self] (incomingEvent) -> NSEvent! in

			if self?.checkForHotkey(incomingEvent) ?? false {
				return nil
			}

			if let w = incomingEvent.window as? MenuWindow {
				//DLog("Keycode: %d", incomingEvent.keyCode)

				switch incomingEvent.keyCode {
				case 123: // left
					fallthrough
				case 124: // right
					if !(
						(incomingEvent.modifierFlags.intersect(NSEventModifierFlags.CommandKeyMask)) == NSEventModifierFlags.CommandKeyMask
						&& (incomingEvent.modifierFlags.intersect(NSEventModifierFlags.AlternateKeyMask)) == NSEventModifierFlags.AlternateKeyMask
						) {
							return incomingEvent
					}

					if app.isManuallyScrolling && w.table.selectedRow == -1 { return nil }

					if Repo.interestedInPrs() && Repo.interestedInIssues(), let s = self {
						if w == s.prMenu {
							s.showMenu(s.issuesMenu)
						} else if w == self?.issuesMenu {
							s.showMenu(s.prMenu)
						}
					}
					return nil
				case 125: // down
					if incomingEvent.modifierFlags.intersect(NSEventModifierFlags.ShiftKeyMask) == NSEventModifierFlags.ShiftKeyMask {
						return incomingEvent
					}
					if app.isManuallyScrolling && w.table.selectedRow == -1 { return nil }
					var i = w.table.selectedRow + 1
					if i < w.table.numberOfRows {
						while self?.dataItemAtRow(i, inMenu: w) == nil { i += 1 }
						self?.scrollToIndex(i, inMenu: w)
					}
					return nil
				case 126: // up
					if incomingEvent.modifierFlags.intersect(NSEventModifierFlags.ShiftKeyMask) == NSEventModifierFlags.ShiftKeyMask {
						return incomingEvent
					}
					if app.isManuallyScrolling && w.table.selectedRow == -1 { return nil }
					var i = w.table.selectedRow - 1
					if i > 0 {
						while self?.dataItemAtRow(i, inMenu: w) == nil { i -= 1 }
						self?.scrollToIndex(i, inMenu: w)
					}
					return nil
				case 36: // enter
					if let c = NSTextInputContext.currentInputContext() where c.client.hasMarkedText() {
						return incomingEvent
					}
					if app.isManuallyScrolling && w.table.selectedRow == -1 { return nil }
					if let dataItem = self?.dataItemAtRow(w.table.selectedRow, inMenu: w) {
						let isAlternative = ((incomingEvent.modifierFlags.intersect(NSEventModifierFlags.AlternateKeyMask)) == NSEventModifierFlags.AlternateKeyMask)
						self?.dataItemSelected(dataItem, alternativeSelect: isAlternative)
					}
					return nil
				case 53: // escape
					self?.closeMenu(w)
					return nil
				default:
					break
				}
			}
			return incomingEvent
		}
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
		atNextEvent {
			inMenu.table.selectRowIndexes(NSIndexSet(index: i), byExtendingSelection: false)
			return
		}
	}

	func focusedItem() -> ListableItem? {
		if prMenu.visible {
			let row = prMenu.table.selectedRow
			var pr: PullRequest?
			if row >= 0 {
				prMenu.table.deselectAll(nil)
				pr = pullRequestDelegate.pullRequestAtRow(row)
			}
			atNextEvent { [weak self] in
				self?.prMenu.table.selectRowIndexes(NSIndexSet(index: row), byExtendingSelection: false)
			}
			return pr
		} else if issuesMenu.visible {
			let row = issuesMenu.table.selectedRow
			var i: Issue?
			if row >= 0 {
				issuesMenu.table.deselectAll(nil)
				i = issuesDelegate.issueAtRow(row)
			}
			atNextEvent { [weak self] in
				self?.issuesMenu.table.selectRowIndexes(NSIndexSet(index: row), byExtendingSelection: false)
			}
			return i
		} else {
			return nil
		}
	}

	private func checkForHotkey(incomingEvent: NSEvent) -> Bool {
		var check = 0

		if Settings.hotkeyCommandModifier {
			check += (incomingEvent.modifierFlags.intersect(NSEventModifierFlags.CommandKeyMask)) == NSEventModifierFlags.CommandKeyMask ? 1 : -1
		} else {
			check += (incomingEvent.modifierFlags.intersect(NSEventModifierFlags.CommandKeyMask)) == NSEventModifierFlags.CommandKeyMask ? -1 : 1
		}

		if Settings.hotkeyControlModifier {
			check += (incomingEvent.modifierFlags.intersect(NSEventModifierFlags.ControlKeyMask)) == NSEventModifierFlags.ControlKeyMask ? 1 : -1
		} else {
			check += (incomingEvent.modifierFlags.intersect(NSEventModifierFlags.ControlKeyMask)) == NSEventModifierFlags.ControlKeyMask ? -1 : 1
		}

		if Settings.hotkeyOptionModifier {
			check += (incomingEvent.modifierFlags.intersect(NSEventModifierFlags.AlternateKeyMask)) == NSEventModifierFlags.AlternateKeyMask ? 1 : -1
		} else {
			check += (incomingEvent.modifierFlags.intersect(NSEventModifierFlags.AlternateKeyMask)) == NSEventModifierFlags.AlternateKeyMask ? -1 : 1
		}

		if Settings.hotkeyShiftModifier {
			check += (incomingEvent.modifierFlags.intersect(NSEventModifierFlags.ShiftKeyMask)) == NSEventModifierFlags.ShiftKeyMask ? 1 : -1
		} else {
			check += (incomingEvent.modifierFlags.intersect(NSEventModifierFlags.ShiftKeyMask)) == NSEventModifierFlags.ShiftKeyMask ? -1 : 1
		}

		let keyMap = [
			"A": 0, "B": 11, "C": 8, "D": 2, "E": 14, "F": 3, "G": 5, "H": 4, "I": 34, "J": 38,
			"K": 40, "L": 37, "M": 46, "N": 45, "O": 31, "P": 35, "Q": 12, "R": 15, "S": 1,
			"T": 17, "U": 32, "V": 9, "W": 13, "X": 7, "Y": 16, "Z": 6 ];

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
	func showPreferencesWindow() {
		if preferencesWindowController == nil {
			preferencesWindowController = NSWindowController(windowNibName:"PreferencesWindow")
		}
		if let w = preferencesWindowController!.window as? PreferencesWindow {
			w.level = Int(CGWindowLevelForKey(CGWindowLevelKey.FloatingWindowLevelKey))
			w.center()
			w.makeKeyAndOrderFront(self)
			preferencesWindow = w
		}
	}
	func closedPreferencesWindow() {
		preferencesWindow = nil
		preferencesWindowController = nil
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
			if #available(OSX 10.10, *) {
				let c = NSAppearance.currentAppearance()
				if c.respondsToSelector(Selector("allowsVibrancy")) {
					self?.darkMode = c.name.rangeOfString(NSAppearanceNameVibrantDark) != nil
					return
				}
			}
			self?.darkMode = false
		}
	}

	private func setupDarkModeMonitoring() {
		NSDistributedNotificationCenter.defaultCenter().addObserver(self, selector: #selector(OSX_AppDelegate.checkDarkMode), name: "AppleInterfaceThemeChangedNotification", object: nil)
		checkDarkMode()
	}
}
