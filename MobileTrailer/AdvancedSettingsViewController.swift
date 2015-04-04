
import UIKit

class AdvancedSettingsViewController: UITableViewController, PickerViewControllerDelegate {

	required init(coder aDecoder: NSCoder) {
		settingsChangedTimer = PopTimer(timeInterval: 1.0) {
			app.refreshMainList()
		}
		super.init(coder: aDecoder)
	}

	private var settingsChangedTimer: PopTimer

	// for the picker
	private var valuesToPush: [String]?
	private var pickerName: String?
	private var selectedIndexPath: NSIndexPath?
	private var previousValue: Int?

	@IBAction func done(sender: UIBarButtonItem) {
		if app.preferencesDirty { app.startRefresh() }
		dismissViewControllerAnimated(true, completion: nil)
	}

	private enum Section: Int {
		case Refresh, Display, Issues, Comments, Repos, StausesAndLabels, History, Confirm, Sort, Misc
		static let rowCounts = [3, 8, 2, 7, 1, 6, 3, 2, 3, 1]
		static let allNames = ["Auto Refresh", "Display", "Issues", "Comments", "Repositories", "Statuses & Labels", "History", "Don't confirm when", "Sorting", "Misc"]
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

	private enum HandlingPolicy: Int {
		case Own, All, None
		static let allTitles = ["Keep My Own", "Keep All", "Don't Keep"]
		func name() -> String {
			return HandlingPolicy.allTitles[rawValue]
		}
	}

	private func check(setting: Bool) -> UITableViewCellAccessoryType {
		return setting ? UITableViewCellAccessoryType.Checkmark : UITableViewCellAccessoryType.None
	}

	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier("Cell") as! UITableViewCell
		cell.accessoryType = UITableViewCellAccessoryType.None
		cell.detailTextLabel?.text = " "

		if indexPath.section == Section.Refresh.rawValue {
			switch indexPath.row {
			case 0:
				cell.textLabel?.text = "Foreground refresh interval"
				cell.detailTextLabel?.text = String(format: "%.0f seconds", Settings.refreshPeriod)
			case 1:
				cell.textLabel?.text = "Background refresh interval (minimum)"
				cell.detailTextLabel?.text = String(format: "%.0f minutes", Settings.backgroundRefreshPeriod/60.0)
			case 2:
				cell.textLabel?.text = "Watchlist refresh interval"
				cell.detailTextLabel?.text = String(format: "%.0f hours", Settings.newRepoCheckPeriod)
			default: break
			}
		} else if indexPath.section == Section.Display.rawValue {
			switch indexPath.row {
			case 0:
				cell.textLabel?.text = "Display creation instead of activity times"
				cell.accessoryType = check(Settings.showCreatedInsteadOfUpdated)
			case 1:
				cell.textLabel?.text = "Hide 'All' section"
				cell.accessoryType = check(Settings.hideAllPrsSection)
			case 2:
				cell.textLabel?.text = "Move assigned items to 'Mine'"
				cell.accessoryType = check(Settings.moveAssignedPrsToMySection)
			case 3:
				cell.textLabel?.text = "Announce unmergeable PRs only in 'Mine'/'Participated'"
				cell.accessoryType = check(Settings.markUnmergeableOnUserSectionsOnly)
			case 4:
				cell.textLabel?.text = "Display repository names"
				cell.accessoryType = check(Settings.showReposInName)
			case 5:
				cell.textLabel?.text = "Include repository names in filtering"
				cell.accessoryType = check(Settings.includeReposInFilter)
			case 6:
				cell.textLabel?.text = "Include labels in filtering"
				cell.accessoryType = check(Settings.includeLabelsInFilter)
			case 7:
				cell.textLabel?.text = "Hide descriptions in watch detail views"
				cell.accessoryType = check(Settings.hideDescriptionInWatchDetail)
			default: break
			}
		} else if indexPath.section == Section.Issues.rawValue {
			switch indexPath.row {
			case 0:
				cell.textLabel?.text = "Sync and display issues"
				cell.accessoryType = check(Settings.showIssuesMenu)
			case 1:
				cell.textLabel?.text = "Show issues instead of PRs in watch glances"
				cell.accessoryType = check(Settings.showIssuesInGlance)
			default: break
			}
		} else if indexPath.section == Section.Comments.rawValue {
			switch indexPath.row {
			case 0:
				cell.textLabel?.text = "Display comment badges and alerts for all items"
				cell.accessoryType = check(Settings.showCommentsEverywhere)
			case 1:
				cell.textLabel?.text = "Only display items with unread comments"
				cell.accessoryType = check(Settings.shouldHideUncommentedRequests)
			case 2:
				cell.textLabel?.text = "Move items menitoning me to 'Participated'"
				cell.accessoryType = check(Settings.autoParticipateInMentions)
			case 3:
				cell.textLabel?.text = "Move items menitoning my teams to 'Participated'"
				cell.accessoryType = check(Settings.autoParticipateOnTeamMentions)
			case 4:
				cell.textLabel?.text = "Open items at first unread comment"
				cell.accessoryType = check(Settings.openPrAtFirstUnreadComment)
			case 5:
				cell.textLabel?.text = "Block comment notifications from usernames..."
				cell.accessoryType = UITableViewCellAccessoryType.DisclosureIndicator
			case 6:
				cell.textLabel?.text = "Disable all comment notifications"
				cell.accessoryType = check(Settings.disableAllCommentNotifications)
			default: break
			}
		} else if indexPath.section == Section.Repos.rawValue {
			switch indexPath.row {
			case 0:
				cell.textLabel?.text = "Auto-hide new repositories in your watchlist"
				cell.accessoryType = check(Settings.hideNewRepositories)
			default: break
			}
		} else if indexPath.section == Section.StausesAndLabels.rawValue {
			switch indexPath.row {
			case 0:
				cell.textLabel?.text = "Show statuses"
				cell.accessoryType = check(Settings.showStatusItems)
			case 1:
				cell.textLabel?.text = "Re-query statuses"
				cell.detailTextLabel?.text = Settings.statusItemRefreshInterval == 1 ? "Every refresh" : "Every \(Settings.statusItemRefreshInterval) refreshes"
			case 2:
				cell.textLabel?.text = "Show labels"
				cell.accessoryType = check(Settings.showLabels)
			case 3:
				cell.textLabel?.text = "Re-query labels"
				cell.detailTextLabel?.text = Settings.labelRefreshInterval == 1 ? "Every refresh" : "Every \(Settings.labelRefreshInterval) refreshes"
			case 4:
				cell.textLabel?.text = "Notifications for new statuses"
				cell.accessoryType = check(Settings.notifyOnStatusUpdates)
			case 5:
				cell.textLabel?.text = "... new statuses for all PRs"
				cell.accessoryType = check(Settings.notifyOnStatusUpdatesForAllPrs)
			default: break
			}
		} else if indexPath.section == Section.History.rawValue {
			switch indexPath.row {
			case 0:
				cell.textLabel?.text = "When something is merged"
				cell.detailTextLabel?.text = HandlingPolicy(rawValue: Settings.mergeHandlingPolicy)?.name()
			case 1:
				cell.textLabel?.text = "When something is closed"
				cell.detailTextLabel?.text = HandlingPolicy(rawValue: Settings.closeHandlingPolicy)?.name()
			case 2:
				cell.textLabel?.text = "Don't keep PRs merged by me"
				cell.accessoryType = check(Settings.dontKeepPrsMergedByMe)
			default: break
			}
		} else if indexPath.section == Section.Confirm.rawValue {
			switch indexPath.row {
			case 0:
				cell.textLabel?.text = "Removing all merged items"
				cell.accessoryType = check(Settings.dontAskBeforeWipingMerged)
			case 1:
				cell.textLabel?.text = "Removing all closed items"
				cell.accessoryType = check(Settings.dontAskBeforeWipingClosed)
			default: break
			}
		} else if indexPath.section == Section.Sort.rawValue {
			switch indexPath.row {
			case 0:
				cell.textLabel?.text = "Direction"
				cell.detailTextLabel?.text = Settings.sortDescending ? "Reverse" : "Normal"
			case 1:
				cell.textLabel?.text = "Criterion"
				if Settings.sortDescending {
					cell.detailTextLabel?.text = ReverseSorting(rawValue: Settings.sortMethod)?.name()
				} else {
					cell.detailTextLabel?.text = NormalSorting(rawValue: Settings.sortMethod)?.name()
				}
			case 2:
				cell.textLabel?.text = "Group by repository"
				cell.accessoryType = check(Settings.groupByRepo)
			default: break
			}
		} else if indexPath.section == Section.Misc.rawValue {
			switch indexPath.row {
			case 0:
				cell.textLabel?.text = "Log activity to console"
				cell.accessoryType = check(Settings.logActivityToConsole)
			default: break
			}
		}
		return cell
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
				Settings.hideAllPrsSection = !Settings.hideAllPrsSection
				settingsChangedTimer.push()
			case 2:
				Settings.moveAssignedPrsToMySection = !Settings.moveAssignedPrsToMySection
				settingsChangedTimer.push()
			case 3:
				Settings.markUnmergeableOnUserSectionsOnly = !Settings.markUnmergeableOnUserSectionsOnly
				settingsChangedTimer.push()
			case 4:
				Settings.showReposInName = !Settings.showReposInName
				settingsChangedTimer.push()
			case 5:
				Settings.includeReposInFilter = !Settings.includeReposInFilter
			case 6:
				Settings.includeLabelsInFilter = !Settings.includeLabelsInFilter
			case 7:
				Settings.hideDescriptionInWatchDetail = !Settings.hideDescriptionInWatchDetail
			default: break
			}
		} else if indexPath.section == Section.Issues.rawValue {
			switch indexPath.row {
			case 0:
				Settings.showIssuesMenu = !Settings.showIssuesMenu
				if Settings.showIssuesMenu {
					for r in DataItem.allItemsOfType("Repo", inMoc: mainObjectContext) as! [Repo] {
						r.dirty = true
						r.lastDirtied = NSDate.distantPast() as? NSDate
					}
					app.preferencesDirty = true
				} else {
					for i in DataItem.allItemsOfType("Issue", inMoc: mainObjectContext) as! [Issue] {
						i.postSyncAction = PostSyncAction.Delete.rawValue
					}
					DataItem.nukeDeletedItemsInMoc(mainObjectContext)
				}
				settingsChangedTimer.push()
			case 1:
				Settings.showIssuesInGlance = !Settings.showIssuesInGlance
			default: break
			}
		} else if indexPath.section == Section.Comments.rawValue {
			switch indexPath.row {
			case 0:
				Settings.showCommentsEverywhere = !Settings.showCommentsEverywhere
				settingsChangedTimer.push()
			case 1:
				Settings.shouldHideUncommentedRequests = !Settings.shouldHideUncommentedRequests
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
			switch indexPath.row {
			case 0:
				Settings.hideNewRepositories = !Settings.hideNewRepositories
			default: break
			}
		} else if indexPath.section == Section.StausesAndLabels.rawValue {
			switch indexPath.row {
			case 0:
				Settings.showStatusItems = !Settings.showStatusItems
				api.resetAllStatusChecks()
				if Settings.showStatusItems {
					for r in DataItem.allItemsOfType("Repo", inMoc: mainObjectContext) as! [Repo] {
						r.dirty = true
						r.lastDirtied = NSDate.distantPast() as? NSDate
					}
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
					for r in DataItem.allItemsOfType("Repo", inMoc: mainObjectContext) as! [Repo] {
						r.dirty = true
						r.lastDirtied = NSDate.distantPast() as? NSDate
					}
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
				valuesToPush = HandlingPolicy.allTitles
				performSegueWithIdentifier("showPicker", sender: self)
			case 1:
				selectedIndexPath = indexPath;
				previousValue = Settings.closeHandlingPolicy
				pickerName = tableView.cellForRowAtIndexPath(indexPath)?.textLabel?.text ?? "Unknown Picker"
				valuesToPush = HandlingPolicy.allTitles
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
				tableView.reloadData()
				if Settings.logActivityToConsole {
					UIAlertView(title: "Warning",
						message: "Logging is a feature meant to aid error reporting, having it constantly enabled will cause this app to be less responsive and use more battery",
						delegate: nil,
						cancelButtonTitle: "OK").show()
				}
			default: break
			}
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
			} else if sip.section == Section.Sort.rawValue {
				Settings.sortMethod = Int(didSelectIndexPath.row)
				settingsChangedTimer.push()
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
			tableView.reloadData()
			selectedIndexPath = nil
		}
	}
}
