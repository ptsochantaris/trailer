
final class MenuBarSet {

	private let prMenuController = NSWindowController(windowNibName:"MenuWindow")
	private let issuesMenuController = NSWindowController(windowNibName:"MenuWindow")

	let prMenu: MenuWindow
	let issuesMenu: MenuWindow
	let viewCriterion: GroupingCriterion?

	var prFilterTimer: PopTimer!
	var issuesFilterTimer: PopTimer!

	var forceVisible = false

	init(viewCriterion: GroupingCriterion?, delegate: NSWindowDelegate) {
		self.viewCriterion = viewCriterion

		prMenu = prMenuController.window as! MenuWindow
		prMenu.itemDelegate = ItemDelegate(type: "PullRequest", sections: Section.prMenuTitles, removeButtonsInSections: [Section.Merged.prMenuName(), Section.Closed.prMenuName()], viewCriterion: viewCriterion)
		prMenu.delegate = delegate

		issuesMenu = issuesMenuController.window as! MenuWindow
		issuesMenu.itemDelegate = ItemDelegate(type: "Issue", sections: Section.issueMenuTitles, removeButtonsInSections: [Section.Closed.issuesMenuName()], viewCriterion: viewCriterion)
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

	func prepareForRefresh() {

		let grayOut = Settings.grayOutWhenRefreshing

		if prMenu.messageView != nil {
			updatePrMenu()
		}
		prMenu.refreshMenuItem.title = " Refreshing..."
		(prMenu.statusItem?.view as? StatusItemView)?.grayOut = grayOut

		if issuesMenu.messageView != nil {
			updateIssuesMenu()
		}
		issuesMenu.refreshMenuItem.title = " Refreshing..."
		(issuesMenu.statusItem?.view as? StatusItemView)?.grayOut = grayOut
	}

	var allowRefresh = false {
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

	private func updateMenu(type: String,
	                        menu: MenuWindow,
	                        lengthOffset: CGFloat,
	                        totalCount: ()->Int,
	                        hasUnread: ()->Bool,
	                        reasonForEmpty: (String)->NSAttributedString) {

		func redText() -> [String : AnyObject] {
			return [ NSFontAttributeName: NSFont.boldSystemFontOfSize(10),
			         NSForegroundColorAttributeName: MAKECOLOR(0.8, 0.0, 0.0, 1.0) ]
		}

		func normalText() -> [String : AnyObject] {
			return [ NSFontAttributeName: NSFont.menuBarFontOfSize(10),
			         NSForegroundColorAttributeName: NSColor.controlTextColor() ]
		}

		let countString: String
		let attributes: [String : AnyObject]
		let somethingFailed = ApiServer.shouldReportRefreshFailureInMoc(mainObjectContext)
		let preFilterCount: Int

		if somethingFailed && (viewCriterion?.relatedServerFailed ?? true) {
			countString = "X"
			attributes = redText()
			preFilterCount = 0
		} else {

			if Settings.countOnlyListedItems {
				let f = ListableItem.requestForItemsOfType(type, withFilter: menu.filter.stringValue, sectionIndex: -1, criterion: viewCriterion)
				countString = String(mainObjectContext.countForFetchRequest(f, error: nil))
				let fc = ListableItem.requestForItemsOfType(type, withFilter: nil, sectionIndex: -1, criterion: viewCriterion)
				preFilterCount = mainObjectContext.countForFetchRequest(fc, error: nil)
			} else {
				preFilterCount = totalCount()
				countString = String(preFilterCount)
			}

			if hasUnread() {
				attributes = redText()
			} else {
				attributes = normalText()
			}
		}

		DLog("Updating \(type) menu, \(countString) total items")

		let itemLabel = viewCriterion?.label
		let disable = (itemLabel != nil && preFilterCount == 0) && !(forceVisible && type == "PullRequest")

		if disable {
			menu.hideStatusItem()
		} else {

			let shouldGray = Settings.grayOutWhenRefreshing && appIsRefreshing

			let siv = menu.showStatusItem()

			if !(compareDict(siv.textAttributes, to: attributes) && siv.statusLabel == countString && siv.grayOut == shouldGray) {
				// Info has changed, update
				DLog("Updating \(type) status item")
				siv.icon = NSImage(named: "\(type)Icon")!
				siv.textAttributes = attributes
				siv.labelOffset = lengthOffset
				siv.highlighted = menu.visible
				siv.grayOut = shouldGray
				siv.statusLabel = countString
				siv.title = itemLabel
				siv.sizeToFit()
			}
		}

		menu.reload()

		if menu.table.numberOfRows == 0 {
			menu.messageView = MessageView(frame: CGRectMake(0, 0, MENU_WIDTH, 100), message: reasonForEmpty(menu.filter.stringValue))
		}

		menu.sizeAndShow(false)
	}

	func updateIssuesMenu() {

		if Repo.interestedInIssues(viewCriterion?.apiServerId) {

			updateMenu("Issue", menu: issuesMenu, lengthOffset: 2, totalCount: { () -> Int in
				return Issue.countOpenInMoc(mainObjectContext)
			}, hasUnread: { [weak self] () -> Bool in
				return Issue.badgeCountInMoc(mainObjectContext, criterion: self?.viewCriterion) > 0
			}, reasonForEmpty: { [weak self] filter -> NSAttributedString in
				return Issue.reasonForEmptyWithFilter(filter, criterion: self?.viewCriterion)
			})

		} else {
			issuesMenu.hideStatusItem()
		}
	}

	func updatePrMenu() {

		if forceVisible || Repo.interestedInPrs(viewCriterion?.apiServerId) || !Repo.interestedInIssues(viewCriterion?.apiServerId) {

			updateMenu("PullRequest", menu: prMenu, lengthOffset: 0, totalCount: { () -> Int in
				return PullRequest.countOpenInMoc(mainObjectContext)
			}, hasUnread: { [weak self] () -> Bool in
				return PullRequest.badgeCountInMoc(mainObjectContext, criterion: self?.viewCriterion) > 0
			}, reasonForEmpty: { [weak self] filter -> NSAttributedString in
				return PullRequest.reasonForEmptyWithFilter(filter, criterion: self?.viewCriterion)
			})

		} else {
			prMenu.hideStatusItem()
		}

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
