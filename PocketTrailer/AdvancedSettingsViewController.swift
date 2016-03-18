
import UIKit

final class AdvancedSettingsViewController: UITableViewController, PickerViewControllerDelegate, UIDocumentPickerDelegate {

	private var settingsChangedTimer: PopTimer!

	// for the picker
	private var valuesToPush: [String]?
	private var pickerName: String?
	private var selectedIndexPath: NSIndexPath?
	private var previousValue: Int?
	private var showHelp = true

	@IBAction func done(sender: UIBarButtonItem) {
		if app.preferencesDirty { app.startRefresh() }
		dismissViewControllerAnimated(true, completion: nil)
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		tableView.rowHeight = UITableViewAutomaticDimension

		settingsChangedTimer = PopTimer(timeInterval: 1.0) {
			DataManager.postProcessAllItems()
			popupManager.getMasterController().reloadDataWithAnimation(true)
		}

		navigationItem.rightBarButtonItems = [
			UIBarButtonItem(image: UIImage(named: "export"), style: UIBarButtonItemStyle.Plain, target: self, action: Selector("exportSelected:")),
			UIBarButtonItem(image: UIImage(named: "import"), style: UIBarButtonItemStyle.Plain, target: self, action: Selector("importSelected:")),
			UIBarButtonItem(image: UIImage(named: "showHelp"), style: UIBarButtonItemStyle.Plain, target: self, action: Selector("toggleHelp:")),
		]
	}

	func toggleHelp(button: UIBarButtonItem) {
		showHelp = !showHelp
		heightCache.removeAll()
		tableView.reloadSections(NSIndexSet(indexesInRange: NSMakeRange(0, Section.allNames.count)), withRowAnimation: .Automatic)
	}

	private enum Section: Int {
		case Refresh, Display, Filtering, Issues, Comments, Repos, StausesAndLabels, History, Confirm, Sort, Misc
		static let rowCounts = [3, 6, 7, 1, 7, 2, 8, 3, 2, 3, 2]
		static let allNames = ["Auto Refresh", "Display", "Filtering", "Issues", "Comments", "Watchlist", "Statuses & Labels", "History", "Don't confirm when", "Sorting", "Misc"]
	}

	private enum NormalSorting: Int {
		case Age, Activity, Name
		static let allTitles = ["Youngest first", "Most recently active", "Reverse alphabetically"]
		func name() -> String {
			return NormalSorting.allTitles[rawValue]
		}
	}

	private enum ReverseSorting: Int {
		case Age, Activity, Name
		static let allTitles = ["Oldest first", "Inactive for longest", "Alphabetically"]
		func name() -> String {
			return ReverseSorting.allTitles[rawValue]
		}
	}

	private func check(setting: Bool) -> UITableViewCellAccessoryType {
		return setting ? UITableViewCellAccessoryType.Checkmark : UITableViewCellAccessoryType.None
	}

	private func filteringSectionFooter() -> UILabel {
		let p = NSMutableParagraphStyle()
		p.headIndent = 15.0
		p.firstLineHeadIndent = 15.0
		p.tailIndent = -15.0

		let l = UILabel()
		l.attributedText = NSAttributedString(
			string: "You can also use title: server: label: repo: user: number: and status: to filter specific properties, e.g. \"label:bug,suggestion\". Prefix with '!' to exclude some terms.",
			attributes: [
				NSFontAttributeName: UIFont.systemFontOfSize(UIFont.smallSystemFontSize()),
				NSForegroundColorAttributeName: UIColor.lightGrayColor(),
				NSParagraphStyleAttributeName: p,
			])
		l.numberOfLines = 0
		return l
	}

	override func tableView(tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
		if section==Section.Filtering.rawValue {
			return filteringSectionFooter()
		}
		return nil
	}

	override func tableView(tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
		if section==Section.Filtering.rawValue {
			return filteringSectionFooter().sizeThatFits(CGSizeMake(tableView.bounds.size.width, 500.0)).height + 15.0
		}
		return 0.0
	}

	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier("Cell") as! AdvancedSettingsCell
		configureCell(cell, indexPath: indexPath)
		return cell
	}

	private func configureCell(cell: AdvancedSettingsCell, indexPath: NSIndexPath) {
		cell.accessoryType = UITableViewCellAccessoryType.None
		cell.valueLabel.text = " "

		if indexPath.section == Section.Refresh.rawValue {
			switch indexPath.row {
			case 0:
				cell.titleLabel.text = "Foreground refresh interval"
				cell.valueLabel.text = String(format: "%.0f seconds", Settings.refreshPeriod)
				cell.descriptionLabel.text = Settings.refreshPeriodHelp
			case 1:
				cell.titleLabel.text = "Background refresh interval (minimum)"
				cell.valueLabel.text = String(format: "%.0f minutes", Settings.backgroundRefreshPeriod/60.0)
				cell.descriptionLabel.text = Settings.backgroundRefreshPeriodHelp
			case 2:
				cell.titleLabel.text = "Watchlist & team list refresh interval"
				cell.valueLabel.text = String(format: "%.0f hours", Settings.newRepoCheckPeriod)
				cell.descriptionLabel.text = Settings.newRepoCheckPeriodHelp
			default: break
			}
		} else if indexPath.section == Section.Display.rawValue {
			switch indexPath.row {
			case 0:
				cell.titleLabel.text = "Display item creation times instead of update times"
				cell.accessoryType = check(Settings.showCreatedInsteadOfUpdated)
				cell.descriptionLabel.text = Settings.showCreatedInsteadOfUpdatedHelp
			case 1:
				cell.titleLabel.text = "Assigned items"
				cell.valueLabel.text = PRAssignmentPolicy(rawValue: Settings.assignedPrHandlingPolicy)?.name()
				cell.descriptionLabel.text = "How to handle items that have been detected as assigned to you."
			case 2:
				cell.titleLabel.text = "Mark unmergeable PRs only in 'My' or 'Participated' sections"
				cell.accessoryType = check(Settings.markUnmergeableOnUserSectionsOnly)
				cell.descriptionLabel.text = Settings.markUnmergeableOnUserSectionsOnlyHelp
			case 3:
				cell.titleLabel.text = "Display repository names"
				cell.accessoryType = check(Settings.showReposInName)
				cell.descriptionLabel.text = Settings.showReposInNameHelp
			case 4:
				cell.titleLabel.text = "Hide descriptions in Apple Watch detail views"
				cell.accessoryType = check(Settings.hideDescriptionInWatchDetail)
				cell.descriptionLabel.text = Settings.hideDescriptionInWatchDetailHelp
			case 5:
				cell.titleLabel.text = "Open items directly in Safari if internal web view is not already visible."
				cell.accessoryType = check(Settings.openItemsDirectlyInSafari)
				cell.descriptionLabel.text = Settings.openItemsDirectlyInSafariHelp
			default: break
			}
		} else if indexPath.section == Section.Filtering.rawValue {
			switch indexPath.row {
			case 0:
				cell.titleLabel.text = "Include item titles"
				cell.accessoryType = check(Settings.includeTitlesInFilter)
				cell.descriptionLabel.text = Settings.includeTitlesInFilterHelp
			case 1:
				cell.titleLabel.text = "Include repository names "
				cell.accessoryType = check(Settings.includeReposInFilter)
				cell.descriptionLabel.text = Settings.includeReposInFilterHelp
			case 2:
				cell.titleLabel.text = "Include labels"
				cell.accessoryType = check(Settings.includeLabelsInFilter)
				cell.descriptionLabel.text = Settings.includeLabelsInFilterHelp
			case 3:
				cell.titleLabel.text = "Include statuses"
				cell.accessoryType = check(Settings.includeStatusesInFilter)
				cell.descriptionLabel.text = Settings.includeStatusesInFilterHelp
			case 4:
				cell.titleLabel.text = "Include servers"
				cell.accessoryType = check(Settings.includeServersInFilter)
				cell.descriptionLabel.text = Settings.includeServersInFilterHelp
			case 5:
				cell.titleLabel.text = "Include usernames"
				cell.accessoryType = check(Settings.includeUsersInFilter)
				cell.descriptionLabel.text = Settings.includeUsersInFilterHelp
			case 6:
				cell.titleLabel.text = "Include PR or issue numbers"
				cell.accessoryType = check(Settings.includeNumbersInFilter)
				cell.descriptionLabel.text = Settings.includeNumbersInFilterHelp
			default: break
			}
		} else if indexPath.section == Section.Issues.rawValue {
			switch indexPath.row {
			case 0:
				cell.titleLabel.text = "Prefer issues instead of PRs in Apple Watch glances & complications"
				cell.accessoryType = check(Settings.preferIssuesInWatch)
				cell.descriptionLabel.text = Settings.preferIssuesInWatchHelp
			default: break
			}
		} else if indexPath.section == Section.Comments.rawValue {
			switch indexPath.row {
			case 0:
				cell.titleLabel.text = "Badge & send alerts for the 'all' section too"
				cell.accessoryType = check(Settings.showCommentsEverywhere)
				cell.descriptionLabel.text = Settings.showCommentsEverywhereHelp
			case 1:
				cell.titleLabel.text = "Only display items with unread comments"
				cell.accessoryType = check(Settings.hideUncommentedItems)
				cell.descriptionLabel.text = Settings.hideUncommentedItemsHelp
			case 2:
				cell.titleLabel.text = "Move items menitoning me to 'Participated'"
				cell.accessoryType = check(Settings.autoParticipateInMentions)
				cell.descriptionLabel.text = Settings.autoParticipateInMentionsHelp
			case 3:
				cell.titleLabel.text = "Move items menitoning my teams to 'Participated'"
				cell.accessoryType = check(Settings.autoParticipateOnTeamMentions)
				cell.descriptionLabel.text = Settings.autoParticipateOnTeamMentionsHelp
			case 4:
				cell.titleLabel.text = "Open items at first unread comment"
				cell.accessoryType = check(Settings.openPrAtFirstUnreadComment)
				cell.descriptionLabel.text = Settings.openPrAtFirstUnreadCommentHelp
			case 5:
				cell.titleLabel.text = "Block comment notifications from usernames..."
				cell.accessoryType = UITableViewCellAccessoryType.DisclosureIndicator
				cell.descriptionLabel.text = "A list of usernames whose comments you don't want to receive notifications for."
			case 6:
				cell.titleLabel.text = "Disable all comment notifications"
				cell.accessoryType = check(Settings.disableAllCommentNotifications)
				cell.descriptionLabel.text = Settings.disableAllCommentNotificationsHelp
			default: break
			}
		} else if indexPath.section == Section.Repos.rawValue {
			switch indexPath.row {
			case 0:
				cell.titleLabel.text = "PR visibility for new repos"
				cell.valueLabel.text = RepoDisplayPolicy(rawValue: Settings.displayPolicyForNewPrs)?.name()
				cell.descriptionLabel.text = Settings.displayPolicyForNewPrsHelp
			case 1:
				cell.titleLabel.text = "Issue visibility for new repos"
				cell.valueLabel.text = RepoDisplayPolicy(rawValue: Settings.displayPolicyForNewIssues)?.name()
				cell.descriptionLabel.text = Settings.displayPolicyForNewIssuesHelp
			default: break
			}
		} else if indexPath.section == Section.StausesAndLabels.rawValue {
			switch indexPath.row {
			case 0:
				cell.titleLabel.text = "Show statuses"
				cell.accessoryType = check(Settings.showStatusItems)
				cell.descriptionLabel.text = Settings.showStatusItemsHelp
			case 1:
				cell.titleLabel.text = "Re-query statuses"
				cell.valueLabel.text = Settings.statusItemRefreshInterval == 1 ? "Every refresh" : "Every \(Settings.statusItemRefreshInterval) refreshes"
				cell.descriptionLabel.text = Settings.statusItemRefreshIntervalHelp
			case 2:
				cell.titleLabel.text = "Show labels"
				cell.accessoryType = check(Settings.showLabels)
				cell.descriptionLabel.text = Settings.showLabelsHelp
			case 3:
				cell.titleLabel.text = "Re-query labels"
				cell.valueLabel.text = Settings.labelRefreshInterval == 1 ? "Every refresh" : "Every \(Settings.labelRefreshInterval) refreshes"
				cell.descriptionLabel.text = Settings.labelRefreshIntervalHelp
			case 4:
				cell.titleLabel.text = "Notify status changes for my & participated PRs"
				cell.accessoryType = check(Settings.notifyOnStatusUpdates)
				cell.descriptionLabel.text = Settings.notifyOnStatusUpdatesHelp
			case 5:
				cell.titleLabel.text = "...in the 'All' section too"
				cell.accessoryType = check(Settings.notifyOnStatusUpdatesForAllPrs)
				cell.descriptionLabel.text = Settings.notifyOnStatusUpdatesForAllPrsHelp
			case 6:
				cell.titleLabel.text = "Hide PRs whose status items are not all green"
				cell.accessoryType = check(Settings.hidePrsThatArentPassing)
				cell.descriptionLabel.text = Settings.hidePrsThatArentPassingHelp
			case 7:
				cell.titleLabel.text = "...only in the 'All' section"
				cell.accessoryType = check(Settings.hidePrsThatDontPassOnlyInAll)
				cell.descriptionLabel.text = Settings.hidePrsThatDontPassOnlyInAllHelp
			default: break
			}
		} else if indexPath.section == Section.History.rawValue {
			switch indexPath.row {
			case 0:
				cell.titleLabel.text = "When something is merged"
				cell.valueLabel.text = PRHandlingPolicy(rawValue: Settings.mergeHandlingPolicy)?.name()
				cell.descriptionLabel.text = Settings.mergeHandlingPolicyHelp
			case 1:
				cell.titleLabel.text = "When something is closed"
				cell.valueLabel.text = PRHandlingPolicy(rawValue: Settings.closeHandlingPolicy)?.name()
				cell.descriptionLabel.text = Settings.closeHandlingPolicyHelp
			case 2:
				cell.titleLabel.text = "Don't keep PRs merged by me"
				cell.accessoryType = check(Settings.dontKeepPrsMergedByMe)
				cell.descriptionLabel.text = Settings.dontKeepPrsMergedByMeHelp
			default: break
			}
		} else if indexPath.section == Section.Confirm.rawValue {
			switch indexPath.row {
			case 0:
				cell.titleLabel.text = "Removing all merged items"
				cell.accessoryType = check(Settings.dontAskBeforeWipingMerged)
				cell.descriptionLabel.text = Settings.dontAskBeforeWipingMergedHelp
			case 1:
				cell.titleLabel.text = "Removing all closed items"
				cell.accessoryType = check(Settings.dontAskBeforeWipingClosed)
				cell.descriptionLabel.text = Settings.dontAskBeforeWipingClosedHelp
			default: break
			}
		} else if indexPath.section == Section.Sort.rawValue {
			switch indexPath.row {
			case 0:
				cell.titleLabel.text = "Direction"
				cell.valueLabel.text = Settings.sortDescending ? "Reverse" : "Normal"
				cell.descriptionLabel.text = Settings.sortDescendingHelp
			case 1:
				cell.titleLabel.text = "Criterion"
				if Settings.sortDescending {
					cell.valueLabel.text = ReverseSorting(rawValue: Settings.sortMethod)?.name()
				} else {
					cell.valueLabel.text = NormalSorting(rawValue: Settings.sortMethod)?.name()
				}
				cell.descriptionLabel.text = Settings.sortMethodHelp
			case 2:
				cell.titleLabel.text = "Group by repository"
				cell.accessoryType = check(Settings.groupByRepo)
				cell.descriptionLabel.text = Settings.groupByRepoHelp
			default: break
			}
		} else if indexPath.section == Section.Misc.rawValue {
			switch indexPath.row {
			case 0:
				cell.titleLabel.text = "Log activity to console"
				cell.accessoryType = check(Settings.logActivityToConsole)
				cell.descriptionLabel.text = Settings.logActivityToConsoleHelp
			case 1:
				cell.titleLabel.text = "Log API calls to console"
				cell.accessoryType = check(Settings.dumpAPIResponsesInConsole)
				cell.descriptionLabel.text = Settings.dumpAPIResponsesInConsoleHelp
			default: break
			}
		}
		if showHelp {
			cell.detailsBottomAnchor.constant = 6
			cell.detailsTopAnchor.constant = 6
		} else {
			cell.descriptionLabel.text = nil
			cell.detailsBottomAnchor.constant = 4
			cell.detailsTopAnchor.constant = 0
		}
	}

	override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {

		previousValue = nil

		if indexPath.section == Section.Refresh.rawValue {
			pickerName = tableView.cellForRowAtIndexPath(indexPath)?.textLabel?.text ?? "Unknown Value"
			selectedIndexPath = indexPath
			var values = [String]()
			var count=0
			switch indexPath.row {
			case 0:
				// seconds
				for var f=60; f<3600; f+=10 {
					if f == Int(Settings.refreshPeriod) { previousValue = count }
					values.append("\(f) seconds")
					count++
				}
			case 1:
				// minutes
				for var f=10; f<10000; f+=10 {
					if f == Int(Settings.backgroundRefreshPeriod/60.0) { previousValue = count }
					values.append("\(f) minutes")
					count++
				}
			case 2:
				// hours
				for f in 2..<100 {
					if f == Int(Settings.newRepoCheckPeriod) { previousValue = count }
					values.append("\(f) hours")
					count++
				}
			default: break
			}
			valuesToPush = values
			performSegueWithIdentifier("showPicker", sender: self)

		} else if indexPath.section == Section.Display.rawValue {
			switch indexPath.row {
			case 0:
				Settings.showCreatedInsteadOfUpdated = !Settings.showCreatedInsteadOfUpdated
				settingsChangedTimer.push()
			case 1:
				pickerName = tableView.cellForRowAtIndexPath(indexPath)?.textLabel?.text ?? "Unknown Value"
				selectedIndexPath = indexPath
				valuesToPush = PRAssignmentPolicy.labels
				previousValue = Settings.assignedPrHandlingPolicy
				performSegueWithIdentifier("showPicker", sender: self)
			case 2:
				Settings.markUnmergeableOnUserSectionsOnly = !Settings.markUnmergeableOnUserSectionsOnly
				settingsChangedTimer.push()
			case 3:
				Settings.showReposInName = !Settings.showReposInName
				settingsChangedTimer.push()
			case 4:
				Settings.hideDescriptionInWatchDetail = !Settings.hideDescriptionInWatchDetail
			case 5:
				Settings.openItemsDirectlyInSafari = !Settings.openItemsDirectlyInSafari
			default: break
			}
		} else if indexPath.section == Section.Filtering.rawValue {
			switch indexPath.row {
			case 0:
				Settings.includeTitlesInFilter = !Settings.includeTitlesInFilter
			case 1:
				Settings.includeReposInFilter = !Settings.includeReposInFilter
			case 2:
				Settings.includeLabelsInFilter = !Settings.includeLabelsInFilter
			case 3:
				Settings.includeStatusesInFilter = !Settings.includeStatusesInFilter
			case 4:
				Settings.includeServersInFilter = !Settings.includeServersInFilter
			case 5:
				Settings.includeUsersInFilter = !Settings.includeUsersInFilter
			case 6:
				Settings.includeNumbersInFilter = !Settings.includeNumbersInFilter
			default: break
			}
			settingsChangedTimer.push()
		} else if indexPath.section == Section.Issues.rawValue {
			switch indexPath.row {
			case 0:
				Settings.preferIssuesInWatch = !Settings.preferIssuesInWatch
			default: break
			}
		} else if indexPath.section == Section.Comments.rawValue {
			switch indexPath.row {
			case 0:
				Settings.showCommentsEverywhere = !Settings.showCommentsEverywhere
				settingsChangedTimer.push()
			case 1:
				Settings.hideUncommentedItems = !Settings.hideUncommentedItems
				settingsChangedTimer.push()
			case 2:
				Settings.autoParticipateInMentions = !Settings.autoParticipateInMentions
				settingsChangedTimer.push()
			case 3:
				Settings.autoParticipateOnTeamMentions = !Settings.autoParticipateOnTeamMentions
				settingsChangedTimer.push()
			case 4:
				Settings.openPrAtFirstUnreadComment = !Settings.openPrAtFirstUnreadComment
			case 5:
				performSegueWithIdentifier("showBlacklist", sender: self)
			case 6:
				Settings.disableAllCommentNotifications = !Settings.disableAllCommentNotifications
			default: break
			}
		} else if indexPath.section == Section.Repos.rawValue {
			pickerName = tableView.cellForRowAtIndexPath(indexPath)?.textLabel?.text ?? "Unknown Value"
			valuesToPush = RepoDisplayPolicy.labels
			selectedIndexPath = indexPath
			switch indexPath.row {
			case 0:
				previousValue = Settings.displayPolicyForNewPrs
			case 1:
				previousValue = Settings.displayPolicyForNewIssues
			default: break
			}
			performSegueWithIdentifier("showPicker", sender: self)
		} else if indexPath.section == Section.StausesAndLabels.rawValue {
			switch indexPath.row {
			case 0:
				Settings.showStatusItems = !Settings.showStatusItems
				api.resetAllStatusChecks()
				if Settings.showStatusItems {
					ApiServer.resetSyncOfEverything()
				}
				settingsChangedTimer.push()
				app.preferencesDirty = true
			case 1:
				selectedIndexPath = indexPath
				pickerName = tableView.cellForRowAtIndexPath(indexPath)?.textLabel?.text ?? "Unknown Picker"
				var values = [String]()
				var count = 1
				values.append("Every refresh")
				previousValue = 0
				for f in 2..<100 {
					if f == Settings.statusItemRefreshInterval { previousValue = count }
					values.append("Every \(f) refreshes")
					count++
				}
				valuesToPush = values
				performSegueWithIdentifier("showPicker", sender: self)
			case 2:
				Settings.showLabels = !Settings.showLabels
				api.resetAllLabelChecks()
				if Settings.showLabels {
					ApiServer.resetSyncOfEverything()
				}
				settingsChangedTimer.push()
				app.preferencesDirty = true
			case 3:
				selectedIndexPath = indexPath
				pickerName = tableView.cellForRowAtIndexPath(indexPath)?.textLabel?.text ?? "Unknown Picker"
				var values = [String]()
				var count = 1
				values.append("Every refresh")
				previousValue = 0
				for f in 2..<100 {
					if f == Settings.labelRefreshInterval { previousValue = count }
					values.append("Every \(f) refreshes")
					count++
				}
				valuesToPush = values
				performSegueWithIdentifier("showPicker", sender: self)
			case 4:
				Settings.notifyOnStatusUpdates = !Settings.notifyOnStatusUpdates
			case 5:
				Settings.notifyOnStatusUpdatesForAllPrs = !Settings.notifyOnStatusUpdatesForAllPrs
			case 6:
				Settings.hidePrsThatArentPassing = !Settings.hidePrsThatArentPassing
				settingsChangedTimer.push()
			case 7:
				Settings.hidePrsThatDontPassOnlyInAll = !Settings.hidePrsThatDontPassOnlyInAll
				settingsChangedTimer.push()
			default: break
			}
		} else if indexPath.section == Section.History.rawValue {
			switch (indexPath.row) {
			case 0:
				selectedIndexPath = indexPath
				previousValue = Settings.mergeHandlingPolicy
				pickerName = tableView.cellForRowAtIndexPath(indexPath)?.textLabel?.text ?? "Unknown Picker"
				valuesToPush = PRHandlingPolicy.labels
				performSegueWithIdentifier("showPicker", sender: self)
			case 1:
				selectedIndexPath = indexPath;
				previousValue = Settings.closeHandlingPolicy
				pickerName = tableView.cellForRowAtIndexPath(indexPath)?.textLabel?.text ?? "Unknown Picker"
				valuesToPush = PRHandlingPolicy.labels
				performSegueWithIdentifier("showPicker", sender: self)
			case 2:
				Settings.dontKeepPrsMergedByMe = !Settings.dontKeepPrsMergedByMe
			default: break
			}
		} else if indexPath.section == Section.Confirm.rawValue {
			switch indexPath.row {
			case 0:
				Settings.dontAskBeforeWipingMerged = !Settings.dontAskBeforeWipingMerged
			case 1:
				Settings.dontAskBeforeWipingClosed = !Settings.dontAskBeforeWipingClosed
			default: break
			}
		} else if indexPath.section == Section.Sort.rawValue {
			switch (indexPath.row) {
			case 0:
				Settings.sortDescending = !Settings.sortDescending
				settingsChangedTimer.push()
				heightCache.removeAll()
				tableView.reloadData()
			case 1:
				selectedIndexPath = indexPath
				previousValue = Settings.sortMethod
				pickerName = tableView.cellForRowAtIndexPath(indexPath)?.textLabel?.text ?? "Unknown Picker"
				valuesToPush = Settings.sortDescending ? ReverseSorting.allTitles : NormalSorting.allTitles
				performSegueWithIdentifier("showPicker", sender: self)
			case 2:
				Settings.groupByRepo = !Settings.groupByRepo
				settingsChangedTimer.push()
			default: break
			}
		} else if indexPath.section == Section.Misc.rawValue {
			switch indexPath.row {
			case 0:
				Settings.logActivityToConsole = !Settings.logActivityToConsole
				if Settings.logActivityToConsole {
					showMessage("Warning", "Logging is a feature meant to aid error reporting, having it constantly enabled will cause this app to be less responsive and use more battery")
				}
			case 1:
				Settings.dumpAPIResponsesInConsole = !Settings.dumpAPIResponsesInConsole
				if Settings.dumpAPIResponsesInConsole {
					showMessage("Warning", "Logging is a feature meant to aid error reporting, having it constantly enabled will cause this app to be less responsive and use more battery")
				}
			default: break
			}
			heightCache.removeAll()
			tableView.reloadData()
		}
		tableView.reloadRowsAtIndexPaths([indexPath], withRowAnimation:UITableViewRowAnimation.None)
	}

	override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return Section.rowCounts[section]
	}

	override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		return Section.allNames[section]
	}

	override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
		return Section.allNames.count
	}

	private var sizer: AdvancedSettingsCell?
	private var heightCache = [NSIndexPath : CGFloat]()
	override func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
		if sizer == nil {
			sizer = tableView.dequeueReusableCellWithIdentifier("Cell") as? AdvancedSettingsCell
		} else if let h = heightCache[indexPath] {
			//DLog("using cached height for %d - %d", indexPath.section, indexPath.row)
			return h
		}
		configureCell(sizer!, indexPath: indexPath)
		let h = sizer!.systemLayoutSizeFittingSize(CGSizeMake(tableView.bounds.width, UILayoutFittingCompressedSize.height),
			withHorizontalFittingPriority: UILayoutPriorityRequired,
			verticalFittingPriority: UILayoutPriorityFittingSizeLevel).height
		heightCache[indexPath] = h
		return h
	}

	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
		if let p = segue.destinationViewController as? PickerViewController {
			p.delegate = self
			p.title = pickerName
			p.values = valuesToPush
			p.previousValue = previousValue
			pickerName = nil
			valuesToPush = nil
		}
	}

	func pickerViewController(picker: PickerViewController, didSelectIndexPath: NSIndexPath) {
		if let sip = selectedIndexPath {
			if sip.section == Section.Refresh.rawValue {
				if sip.row == 0 {
					Settings.refreshPeriod = Float(didSelectIndexPath.row*10+60)
				} else if sip.row == 1 {
					Settings.backgroundRefreshPeriod = Float((didSelectIndexPath.row*10+10)*60)
				} else if sip.row == 2 {
					Settings.newRepoCheckPeriod = Float(didSelectIndexPath.row+2)
				}
			} else if sip.section == Section.Display.rawValue {
				Settings.assignedPrHandlingPolicy = didSelectIndexPath.row
				settingsChangedTimer.push()
			} else if sip.section == Section.Sort.rawValue {
				Settings.sortMethod = Int(didSelectIndexPath.row)
				settingsChangedTimer.push()
			} else if sip.section == Section.Repos.rawValue {
				if sip.row == 0 {
					Settings.displayPolicyForNewPrs = Int(didSelectIndexPath.row)
				} else if sip.row == 1 {
					Settings.displayPolicyForNewIssues = Int(didSelectIndexPath.row)
				}
			} else if sip.section == Section.History.rawValue {
				if sip.row == 0 {
					Settings.mergeHandlingPolicy = Int(didSelectIndexPath.row)
				} else if sip.row == 1 {
					Settings.closeHandlingPolicy = Int(didSelectIndexPath.row)
				}
			} else if sip.section == Section.StausesAndLabels.rawValue {
				if sip.row == 1 {
					Settings.statusItemRefreshInterval = Int(didSelectIndexPath.row+1)
				} else  if sip.row == 3 {
					Settings.labelRefreshInterval = Int(didSelectIndexPath.row+1)
				}
			}
			heightCache.removeAll()
			tableView.reloadData()
			selectedIndexPath = nil
		}
	}

	/////////////////// Import / Export

	private var tempUrl: NSURL?

	func importSelected(sender: UIBarButtonItem) {
		tempUrl = nil

		let menu = UIDocumentPickerViewController(documentTypes: ["com.housetrip.mobile.trailer.ios.settings"], inMode: UIDocumentPickerMode.Import)
		menu.delegate = self
		popupManager.showPopoverFromViewController(self, fromItem: sender, viewController: menu)
	}

	func exportSelected(sender: UIBarButtonItem) {
		let tempFilePath = NSTemporaryDirectory().stringByAppendingPathComponent("PocketTrailer Settings.trailerSettings")
		tempUrl = NSURL(fileURLWithPath: tempFilePath)
		Settings.writeToURL(tempUrl!)

		let menu = UIDocumentPickerViewController(URL: tempUrl!, inMode: UIDocumentPickerMode.ExportToService)
		menu.delegate = self
		popupManager.showPopoverFromViewController(self, fromItem: sender, viewController: menu)
	}

	func documentPicker(controller: UIDocumentPickerViewController, didPickDocumentAtURL url: NSURL) {
		if tempUrl == nil {
			DLog("Will import settings from %@", url.absoluteString)
			settingsManager.loadSettingsFrom(url, confirmFromView: self) { [weak self] confirmed in
				if confirmed {
					self?.dismissViewControllerAnimated(false, completion: nil)
				}
				self?.documentInteractionCleanup()
			}
		} else {
			DLog("Saved settings to %@", url.absoluteString)
			documentInteractionCleanup()
		}
	}

	func documentPickerWasCancelled(controller: UIDocumentPickerViewController) {
		DLog("Document picker cancelled")
		documentInteractionCleanup()
	}

	func documentInteractionCleanup() {
		if let t = tempUrl {
			do {
				try NSFileManager.defaultManager().removeItemAtURL(t)
			} catch {
				DLog("Temporary file cleanup error: %@", (error as NSError).localizedDescription)
			}
			tempUrl = nil
		}
	}
}
