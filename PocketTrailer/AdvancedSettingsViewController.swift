
import UIKit

final class AdvancedSettingsViewController: UITableViewController, PickerViewControllerDelegate, UIDocumentPickerDelegate {

	private var settingsChangedTimer: PopTimer!

	// for the picker
	private var valuesToPush: [String]?
	private var pickerName: String?
	private var selectedIndexPath: NSIndexPath?
	private var previousValue: Int?

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
			UIBarButtonItem(image: UIImage(named: "import"), style: UIBarButtonItemStyle.Plain, target: self, action: Selector("importSelected:"))
		]
	}

	private enum Section: Int {
		case Refresh, Display, Filtering, Issues, Comments, Repos, StausesAndLabels, History, Confirm, Sort, Misc
		static let rowCounts = [3, 6, 6, 1, 7, 2, 6, 3, 2, 3, 2]
		static let allNames = ["Auto Refresh", "Display", "Filtering", "Issues", "Comments", "Repositories", "Statuses & Labels", "History", "Don't confirm when", "Sorting", "Misc"]
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
			string: "Additionally, you can use title: server: label: repo: user: and status: to filter specific properties, e.g. \"label:bug,suggestion\"",
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
				cell.descriptionLabel.text = "How often to refresh items when the app is active and in the foreground."
			case 1:
				cell.titleLabel.text = "Background refresh interval (minimum)"
				cell.valueLabel.text = String(format: "%.0f minutes", Settings.backgroundRefreshPeriod/60.0)
				cell.descriptionLabel.text = "The minimum amount of time to wait before requesting an update when the app is in the background. Even though this is quite efficient, it's still a good idea to keep this to a high value in order to keep battery and bandwidth use low. The default of half an hour is generally a good number. Please note that iOS may ignore this value and perform background refreshes at longer intervals depending on battery level and other reasons."
			case 2:
				cell.titleLabel.text = "Watchlist & team list refresh interval"
				cell.valueLabel.text = String(format: "%.0f hours", Settings.newRepoCheckPeriod)
				cell.descriptionLabel.text = "How long before reloading your team list and watched repositories from the server. Since this doesn't change often, it's good to keep this as high as possible in order to keep bandwidth use during refreshes as low as possible. Set this to a low value if you often update your watched repositories or teams."
			default: break
			}
		} else if indexPath.section == Section.Display.rawValue {
			switch indexPath.row {
			case 0:
				cell.titleLabel.text = "Display creation instead of activity times"
				cell.accessoryType = check(Settings.showCreatedInsteadOfUpdated)
				cell.descriptionLabel.text = "Trailer will usually display the time of the most recent activity in an item, such as comments. This setting replaces that with the orignal creation time of the item. Together with the sorting options, this is useful for helping prioritise items based on how old, or new, they are."
			case 1:
				cell.titleLabel.text = "Assigned items"
				cell.valueLabel.text = PRAssignmentPolicy(rawValue: Settings.assignedPrHandlingPolicy)?.name()
				cell.descriptionLabel.text = "How to handle items that have been detected as assigned to you."
			case 2:
				cell.titleLabel.text = "Mark unmergeable PRs only in 'My' or 'Participated' sections"
				cell.accessoryType = check(Settings.markUnmergeableOnUserSectionsOnly)
				cell.descriptionLabel.text = "If the server reports a PR as un-mergeable, don't tag this on items in the 'all items' section."
			case 3:
				cell.titleLabel.text = "Display repository names"
				cell.accessoryType = check(Settings.showReposInName)
				cell.descriptionLabel.text = "Show the name of the repository each item comes from."
			case 4:
				cell.titleLabel.text = "Hide descriptions in Apple Watch detail views"
				cell.accessoryType = check(Settings.hideDescriptionInWatchDetail)
				cell.descriptionLabel.text = "When showing the full detail view of items on the Apple Watch, skip showing the description of the item, instead showing only status and comments for it."
			case 5:
				cell.titleLabel.text = "Open items directly in Safari if internal web view is not already visible."
				cell.accessoryType = check(Settings.openItemsDirectlyInSafari)
				cell.descriptionLabel.text = "Directly open items in the Safari browser rather than the internal web view. Especially useful on iPad when using split-screen view, where you can pull in PocktetTrailer from the side but stay in Safari, or on iPhone where you can use the status-bar button as a back button. If the detail view is already visible (for instance when runing in full-screen mode on iPad) the internal view will still get used, even if this option is turned on."
			default: break
			}
		} else if indexPath.section == Section.Filtering.rawValue {
			switch indexPath.row {
			case 0:
				cell.titleLabel.text = "Include item titles"
				cell.accessoryType = check(Settings.includeTitlesInFilter)
				cell.descriptionLabel.text = "Check item titles when selecting items for inclusion in filtered results."
			case 1:
				cell.titleLabel.text = "Include repository names "
				cell.accessoryType = check(Settings.includeReposInFilter)
				cell.descriptionLabel.text = "Check repository names when selecting items for inclusion in filtered results."
			case 2:
				cell.titleLabel.text = "Include labels"
				cell.accessoryType = check(Settings.includeLabelsInFilter)
				cell.descriptionLabel.text = "Check labels of items when selecting items for inclusion in filtered results."
			case 3:
				cell.titleLabel.text = "Include statuses"
				cell.accessoryType = check(Settings.includeStatusesInFilter)
				cell.descriptionLabel.text = "Check status lines of items when selecting items for inclusion in filtered results."
			case 4:
				cell.titleLabel.text = "Include servers"
				cell.accessoryType = check(Settings.includeServersInFilter)
				cell.descriptionLabel.text = "Check the name of the server an item came from when selecting it for inclusion in filtered results."
			case 5:
				cell.titleLabel.text = "Include usernames"
				cell.accessoryType = check(Settings.includeUsersInFilter)
				cell.descriptionLabel.text = "Check the name of the author of an item when selecting it for inclusion in filtered results."
			default: break
			}
		} else if indexPath.section == Section.Issues.rawValue {
			switch indexPath.row {
			case 0:
				cell.titleLabel.text = "Prefer issues instead of PRs in Apple Watch glances & complications"
				cell.accessoryType = check(Settings.preferIssuesInWatch)
				cell.descriptionLabel.text = "In the Apple Watch glance, or when there is only enough space to display one count or set of statistics in complications, prefer the ones for issues rather than the ones for PRs."
			default: break
			}
		} else if indexPath.section == Section.Comments.rawValue {
			switch indexPath.row {
			case 0:
				cell.titleLabel.text = "Display comment badges and alerts for all items"
				cell.accessoryType = check(Settings.showCommentsEverywhere)
				cell.descriptionLabel.text = "Badge and send notificatons for items in the 'all' sections as well as your own and participated ones."
			case 1:
				cell.titleLabel.text = "Only display items with unread comments"
				cell.accessoryType = check(Settings.hideUncommentedItems)
				cell.descriptionLabel.text = "Hide all items except items which have unread comments (items with a red number badge)."
			case 2:
				cell.titleLabel.text = "Move items menitoning me to 'Participated'"
				cell.accessoryType = check(Settings.autoParticipateInMentions)
				cell.descriptionLabel.text = "If your username is mentioned in an item's description or a comment posted inside it, move the item to your 'Participated' section."
			case 3:
				cell.titleLabel.text = "Move items menitoning my teams to 'Participated'"
				cell.accessoryType = check(Settings.autoParticipateOnTeamMentions)
				cell.descriptionLabel.text = "If the name of one of the teams you belong to is mentioned in an item's description or a comment posted inside it, move the item to your 'Participated' section."
			case 4:
				cell.titleLabel.text = "Open items at first unread comment"
				cell.accessoryType = check(Settings.openPrAtFirstUnreadComment)
				cell.descriptionLabel.text = "When opening the web view for an item, skip directly down to the first comment that has not been read, rather than starting from the top of the item's web page."
			case 5:
				cell.titleLabel.text = "Block comment notifications from usernames..."
				cell.accessoryType = UITableViewCellAccessoryType.DisclosureIndicator
				cell.descriptionLabel.text = "A list of usernames whose comments you don't want to receive notifications for."
			case 6:
				cell.titleLabel.text = "Disable all comment notifications"
				cell.accessoryType = check(Settings.disableAllCommentNotifications)
				cell.descriptionLabel.text = "Do not get notified about any comments at all."
			default: break
			}
		} else if indexPath.section == Section.Repos.rawValue {
			switch indexPath.row {
			case 0:
				cell.titleLabel.text = "PR visibility for new repos"
				cell.valueLabel.text = RepoDisplayPolicy(rawValue: Settings.displayPolicyForNewPrs)?.name()
				cell.descriptionLabel.text = "When a new repository is detected in your watchlist, this display policy will be applied by default to pull requests that come from it. You can further customize the display policy for any individual repository from the 'Repositories' tab."
			case 1:
				cell.titleLabel.text = "Issue visibility for new repos"
				cell.valueLabel.text = RepoDisplayPolicy(rawValue: Settings.displayPolicyForNewIssues)?.name()
				cell.descriptionLabel.text = "When a new repository is detected in your watchlist, this display policy will be applied by default to issues that come from it. You can further customize the display policy for any individual repository from the 'Repositories' tab."
			default: break
			}
		} else if indexPath.section == Section.StausesAndLabels.rawValue {
			switch indexPath.row {
			case 0:
				cell.titleLabel.text = "Show statuses"
				cell.accessoryType = check(Settings.showStatusItems)
				cell.descriptionLabel.text = "Show status items, such as CI results or messages from code review services, that are attached to items on the server."
			case 1:
				cell.titleLabel.text = "Re-query statuses"
				cell.valueLabel.text = Settings.statusItemRefreshInterval == 1 ? "Every refresh" : "Every \(Settings.statusItemRefreshInterval) refreshes"
				cell.descriptionLabel.text = "Because querying statuses can be bandwidth-intensive, if you have alot of items in your lists, you may want to raise this to a higher value. You can always see how much API usage you have left per-hour from the server tab."
			case 2:
				cell.titleLabel.text = "Show labels"
				cell.accessoryType = check(Settings.showLabels)
				cell.descriptionLabel.text = "Show labels associated with items, usually a good idea"
			case 3:
				cell.titleLabel.text = "Re-query labels"
				cell.valueLabel.text = Settings.labelRefreshInterval == 1 ? "Every refresh" : "Every \(Settings.labelRefreshInterval) refreshes"
				cell.descriptionLabel.text = "Querying labels can be moderately bandwidth-intensive, but it does involve making some extra API calls. Since labels don't change often, you may want to raise this to a higher value if you have alot of items on your lists. You can always see how much API usage you have left per-hour from the server tab."
			case 4:
				cell.titleLabel.text = "Notifications for new statuses"
				cell.accessoryType = check(Settings.notifyOnStatusUpdates)
				cell.descriptionLabel.text = "Post notifications when status items change. Useful for tracking the CI build state of your own items, for instance."
			case 5:
				cell.titleLabel.text = "... new statuses for all PRs"
				cell.accessoryType = check(Settings.notifyOnStatusUpdatesForAllPrs)
				cell.descriptionLabel.text = "Notificaitons for status items are sent only for your own and particiapted items by default. Select this to receive status update notifications for the items in the 'all' section too."
			default: break
			}
		} else if indexPath.section == Section.History.rawValue {
			switch indexPath.row {
			case 0:
				cell.titleLabel.text = "When something is merged"
				cell.valueLabel.text = PRHandlingPolicy(rawValue: Settings.mergeHandlingPolicy)?.name()
				cell.descriptionLabel.text = "How to handle an item when it is detected as merged."
			case 1:
				cell.titleLabel.text = "When something is closed"
				cell.valueLabel.text = PRHandlingPolicy(rawValue: Settings.closeHandlingPolicy)?.name()
				cell.descriptionLabel.text = "How to handle an item when it is believed to be closed (or has disappeared)."
			case 2:
				cell.titleLabel.text = "Don't keep PRs merged by me"
				cell.accessoryType = check(Settings.dontKeepPrsMergedByMe)
				cell.descriptionLabel.text = "If a PR is detected as merged by you, remove it immediately from the list of merged items"
			default: break
			}
		} else if indexPath.section == Section.Confirm.rawValue {
			switch indexPath.row {
			case 0:
				cell.titleLabel.text = "Removing all merged items"
				cell.accessoryType = check(Settings.dontAskBeforeWipingMerged)
				cell.descriptionLabel.text = "Don't ask for confirmation when you select 'Remove all merged items'. Please note there is no confirmation when selecting this from the Apple Watch, irrespective of this setting."
			case 1:
				cell.titleLabel.text = "Removing all closed items"
				cell.accessoryType = check(Settings.dontAskBeforeWipingClosed)
				cell.descriptionLabel.text = "Don't ask for confirmation when you select 'Remove all closed items'. Please note there is no confirmation when selecting this from the Apple Watch, irrespective of this setting."
			default: break
			}
		} else if indexPath.section == Section.Sort.rawValue {
			switch indexPath.row {
			case 0:
				cell.titleLabel.text = "Direction"
				cell.valueLabel.text = Settings.sortDescending ? "Reverse" : "Normal"
				cell.descriptionLabel.text = "The direction to sort items based on the criterion below. Toggling this option will change the set of options available in the option below to better reflect what that will do."
			case 1:
				cell.titleLabel.text = "Criterion"
				if Settings.sortDescending {
					cell.valueLabel.text = ReverseSorting(rawValue: Settings.sortMethod)?.name()
				} else {
					cell.valueLabel.text = NormalSorting(rawValue: Settings.sortMethod)?.name()
				}
				cell.descriptionLabel.text = "The criterion to use when sorting items."
			case 2:
				cell.titleLabel.text = "Group by repository"
				cell.accessoryType = check(Settings.groupByRepo)
				cell.descriptionLabel.text = "Sort and gather items from the same repository next to each other, before applying the criterion specified above."
			default: break
			}
		} else if indexPath.section == Section.Misc.rawValue {
			switch indexPath.row {
			case 0:
				cell.titleLabel.text = "Log activity to console"
				cell.accessoryType = check(Settings.logActivityToConsole)
				cell.descriptionLabel.text = "This is meant for troubleshooting and should be turned off usually, as it is a performance and security concern. It will output detailed messages about the app's behaviour in the device console."
			case 1:
				cell.titleLabel.text = "Log API calls to console"
				cell.accessoryType = check(Settings.dumpAPIResponsesInConsole)
				cell.descriptionLabel.text = "This is meant for troubleshooting and should be turned off usually, as it is a performance and security concern. It will output the full request and repsonses to and from API servers in the device console."
			default: break
			}
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
					self!.dismissViewControllerAnimated(false, completion: nil)
				}
				self!.documentInteractionCleanup()
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
