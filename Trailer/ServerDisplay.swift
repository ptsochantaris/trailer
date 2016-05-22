//
//  ServerDisplay.swift
//  Trailer
//
//  Created by Paul Tsochantaris on 22/05/2016.
//
//

final class ServerDisplay {

	private let prMenuController = NSWindowController(windowNibName:"MenuWindow")
	private let issuesMenuController = NSWindowController(windowNibName:"MenuWindow")

	let prMenu: MenuWindow
	let issuesMenu: MenuWindow
	let apiServerId: NSManagedObjectID?

	var prFilterTimer: PopTimer!
	var issuesFilterTimer: PopTimer!

	init(apiServer: ApiServer?, delegate: NSWindowDelegate) {
		apiServerId = apiServer?.objectID

		prMenu = prMenuController.window as! MenuWindow
		prMenu.itemDelegate = ItemDelegate(type: "PullRequest", sections: Section.prMenuTitles, removeButtonsInSections: [Section.Merged.prMenuName(), Section.Closed.prMenuName()], apiServer: apiServer)
		prMenu.delegate = delegate

		issuesMenu = issuesMenuController.window as! MenuWindow
		issuesMenu.itemDelegate = ItemDelegate(type: "Issue", sections: Section.issueMenuTitles, removeButtonsInSections: [Section.Closed.issuesMenuName()], apiServer: apiServer)
		issuesMenu.delegate = delegate
	}

	func throwAway() {
		prMenu.hideStatusItem()
		prMenu.close()
		issuesMenu.hideStatusItem()
		issuesMenu.close()
	}

	func setTimers() {
		prFilterTimer = PopTimer(timeInterval: 0.2) { [weak self] in
			if let s = self {
				s.updatePrMenu()
				s.prMenu.scrollToTop()
			}
		}

		issuesFilterTimer = PopTimer(timeInterval: 0.2) { [weak self] in
			if let s = self {
				s.updateIssuesMenu()
				s.issuesMenu.scrollToTop()
			}
		}
	}

	var allowRefresh: Bool = false {
		didSet {
			if allowRefresh {
				prMenu.refreshMenuItem.target = prMenu
				prMenu.refreshMenuItem.action = #selector(MenuWindow.refreshSelected(_:))
				issuesMenu.refreshMenuItem.target = issuesMenu
				issuesMenu.refreshMenuItem.action = #selector(MenuWindow.refreshSelected(_:))
			} else {
				prMenu.refreshMenuItem.action = nil
				prMenu.refreshMenuItem.target = nil
				issuesMenu.refreshMenuItem.action = nil
				issuesMenu.refreshMenuItem.target = nil
			}
		}
	}

	func updateIssuesMenu() {

		if Repo.interestedInIssues(apiServerId) {
			issuesMenu.showStatusItem()
		} else {
			issuesMenu.hideStatusItem()
			return
		}

		let countString: String
		let attributes: [String : AnyObject]
		if ApiServer.shouldReportRefreshFailureInMoc(mainObjectContext) {
			countString = "X"
			attributes = redText()
		} else {

			if Settings.countOnlyListedItems {
				let f = ListableItem.requestForItemsOfType("Issue", withFilter: issuesMenu.filter.stringValue, sectionIndex: -1, apiServerId: apiServerId)
				countString = String(mainObjectContext.countForFetchRequest(f, error: nil))
			} else {
				countString = String(Issue.countOpenInMoc(mainObjectContext))
			}

			if Issue.badgeCountInMoc(mainObjectContext, apiServerId: apiServerId) > 0 {
				attributes = redText()
			} else {
				attributes = normalText()
			}
		}

		DLog("Updating issues menu, \(countString) total items")

		let width = countString.sizeWithAttributes(attributes).width

		let H = NSStatusBar.systemStatusBar().thickness
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
				if let aid = S.apiServerId, a = try! mainObjectContext.existingObjectWithID(aid) as? ApiServer {
					siv.serverTitle = a.label
				}
				siv.tappedCallback = { [weak S] in
					if let S = S {
						let m = S.issuesMenu
						if m.visible {
							m.closeMenu()
						} else {
							app.showMenu(m)
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

	private func redText() -> [String : AnyObject] {
		return [ NSFontAttributeName: NSFont.boldSystemFontOfSize(10),
		         NSForegroundColorAttributeName: MAKECOLOR(0.8, 0.0, 0.0, 1.0) ]
	}

	private func normalText() -> [String : AnyObject] {
		return [ NSFontAttributeName: NSFont.menuBarFontOfSize(10),
		         NSForegroundColorAttributeName: NSColor.controlTextColor() ]
	}

	func updatePrMenu() {

		if Repo.interestedInPrs(apiServerId) || !Repo.interestedInIssues(apiServerId) {
			prMenu.showStatusItem()
		} else {
			prMenu.hideStatusItem()
			return
		}

		let countString: String
		let attributes: [String : AnyObject]
		let somethingFailed = ApiServer.shouldReportRefreshFailureInMoc(mainObjectContext)

		if somethingFailed && apiServerId == nil {
			countString = "X"
			attributes = redText()
		} else if somethingFailed, let aid = apiServerId, a = try! mainObjectContext.existingObjectWithID(aid) as? ApiServer where !(a.lastSyncSucceeded?.boolValue ?? true) {
			countString = "X"
			attributes = redText()
		} else {

			if Settings.countOnlyListedItems {
				let f = ListableItem.requestForItemsOfType("PullRequest", withFilter: prMenu.filter.stringValue, sectionIndex: -1, apiServerId: apiServerId)
				countString = String(mainObjectContext.countForFetchRequest(f, error: nil))
			} else {
				countString = String(PullRequest.countOpenInMoc(mainObjectContext))
			}

			if PullRequest.badgeCountInMoc(mainObjectContext, apiServerId: apiServerId) > 0 {
				attributes = redText()
			} else {
				attributes = normalText()
			}
		}

		DLog("Updating PR menu, \(countString) total items")

		let width = countString.sizeWithAttributes(attributes).width

		let H = NSStatusBar.systemStatusBar().thickness
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
				if let aid = S.apiServerId, a = try! mainObjectContext.existingObjectWithID(aid) as? ApiServer {
					siv.serverTitle = a.label
				}
				siv.tappedCallback = { [weak S] in
					if let S = S {
						let m = S.prMenu
						if m.visible {
							m.closeMenu()
						} else {
							app.showMenu(m)
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
}
