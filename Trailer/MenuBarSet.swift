
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
		prMenu.itemDelegate = ItemDelegate(type: "PullRequest", sections: Section.prMenuTitles, removeButtonsInSections: [Section.merged.prMenuName(), Section.closed.prMenuName()], viewCriterion: viewCriterion)
		prMenu.delegate = delegate

		issuesMenu = issuesMenuController.window as! MenuWindow
		issuesMenu.itemDelegate = ItemDelegate(type: "Issue", sections: Section.issueMenuTitles, removeButtonsInSections: [Section.closed.issuesMenuName()], viewCriterion: viewCriterion)
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

	private static let redText = [ NSFontAttributeName: NSFont.boldSystemFont(ofSize: 10),
	                               NSForegroundColorAttributeName: MAKECOLOR(0.8, 0.0, 0.0, 1.0) ]

	private static let normalText = [ NSFontAttributeName: NSFont.menuBarFont(ofSize: 10),
	                                  NSForegroundColorAttributeName: NSColor.controlTextColor ]

	private func updateMenu(_ type: String,
	                        menu: MenuWindow,
	                        lengthOffset: CGFloat,
	                        totalCount: ()->Int,
	                        hasUnread: ()->Bool,
	                        reasonForEmpty: (String)->NSAttributedString) {

		let countString: String
		let somethingFailed = ApiServer.shouldReportRefreshFailure(in: mainObjectContext) && (viewCriterion?.relatedServerFailed ?? true)
		let attributes = somethingFailed || hasUnread() ? MenuBarSet.redText : MenuBarSet.normalText
		let preFilterCount: Int

		if Settings.countOnlyListedItems {
			let f = ListableItem.requestForItems(ofType: type, withFilter: menu.filter.stringValue, sectionIndex: -1, criterion: viewCriterion)
			countString = somethingFailed ? "X" : String(try! mainObjectContext.count(for: f))
			let fc = ListableItem.requestForItems(ofType: type, withFilter: nil, sectionIndex: -1, criterion: viewCriterion)
			preFilterCount = try! mainObjectContext.count(for: fc)
		} else {
			preFilterCount = totalCount()
			countString = somethingFailed ? "X" : String(preFilterCount)
		}

		DLog("Updating \(type) menu, \(countString) total items")

		let itemLabel = viewCriterion?.label
		let disable = itemLabel != nil && preFilterCount == 0 && !(forceVisible && type == "PullRequest")

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
				siv.highlighted = menu.isVisible
				siv.grayOut = shouldGray
				siv.statusLabel = countString
				siv.title = itemLabel
				siv.sizeToFit()
			}
		}

		menu.reload()

		if menu.table.numberOfRows == 0 {
			menu.messageView = MessageView(frame: CGRect(x: 0, y: 0, width: MENU_WIDTH, height: 100), message: reasonForEmpty(menu.filter.stringValue))
		}

		menu.size(andShow: false)
	}

	func updateIssuesMenu() {

		if Repo.interestedInIssues(viewCriterion?.apiServerId) {

			updateMenu("Issue", menu: issuesMenu, lengthOffset: 2, totalCount: { () -> Int in
				return Issue.countOpen(in: mainObjectContext)
			}, hasUnread: { [weak self] () -> Bool in
				return Issue.badgeCount(in: mainObjectContext, criterion: self?.viewCriterion) > 0
			}, reasonForEmpty: { [weak self] filter -> NSAttributedString in
				return Issue.reasonForEmpty(with: filter, criterion: self?.viewCriterion)
			})

		} else {
			issuesMenu.hideStatusItem()
		}
	}

	func updatePrMenu() {

		if forceVisible || Repo.interestedInPrs(viewCriterion?.apiServerId) || !Repo.interestedInIssues(viewCriterion?.apiServerId) {

			updateMenu("PullRequest", menu: prMenu, lengthOffset: 0, totalCount: { () -> Int in
				return PullRequest.countOpen(in: mainObjectContext)
			}, hasUnread: { [weak self] () -> Bool in
				return PullRequest.badgeCount(in: mainObjectContext, criterion: self?.viewCriterion) > 0
			}, reasonForEmpty: { [weak self] filter -> NSAttributedString in
				return PullRequest.reasonForEmpty(with: filter, criterion: self?.viewCriterion)
			})

		} else {
			prMenu.hideStatusItem()
		}

	}

	private func compareDict(_ from: [String : AnyObject], to: [String : AnyObject]) -> Bool {
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
