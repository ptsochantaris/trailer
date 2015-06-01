//
//  RepoSettingsViewController.swift
//  Trailer
//
//  Created by Paul Tsochantaris on 25/05/2015.
//
//

import UIKit

class RepoSettingsViewController: UITableViewController {

	var repo: Repo?
	var allPrsIndex: Int = -1
	var allIssuesIndex: Int = -1

	private let settingsChangedTimer: PopTimer

	required init(coder aDecoder: NSCoder) {
		settingsChangedTimer = PopTimer(timeInterval: 1.0) {
			DataManager.postProcessAllItems()
			popupManager.getMasterController().reloadDataWithAnimation(true)
		}
		super.init(coder: aDecoder)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		if repo == nil {
			title = "All Repos..."
		}
	}

	override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
		return 2
	}

	override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return RepoDisplayPolicy.labels.count
	}

	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier("Cell") as! UITableViewCell
		if repo == nil {
			if indexPath.section == 0 {
				cell.accessoryType = (allPrsIndex==indexPath.row) ? UITableViewCellAccessoryType.Checkmark : UITableViewCellAccessoryType.None
			} else {
				cell.accessoryType = (allIssuesIndex==indexPath.row) ? UITableViewCellAccessoryType.Checkmark : UITableViewCellAccessoryType.None
			}
		} else {
			if indexPath.section == 0 {
				cell.accessoryType = (repo?.displayPolicyForPrs?.integerValue==indexPath.row) ? UITableViewCellAccessoryType.Checkmark : UITableViewCellAccessoryType.None
			} else {
				cell.accessoryType = (repo?.displayPolicyForIssues?.integerValue==indexPath.row) ? UITableViewCellAccessoryType.Checkmark : UITableViewCellAccessoryType.None
			}
		}
		cell.selectionStyle = cell.accessoryType==UITableViewCellAccessoryType.Checkmark ? UITableViewCellSelectionStyle.None : UITableViewCellSelectionStyle.Default
		cell.textLabel?.text = RepoDisplayPolicy.labels[indexPath.row]
		return cell
	}

	override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		return section==0 ? "Pull Requests" : "Issues"
	}

	override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
		if repo == nil {
			if indexPath.section == 0 {
				allPrsIndex = indexPath.row
				for r in Repo.allItemsOfType("Repo", inMoc: mainObjectContext) as! [Repo] {
					r.displayPolicyForPrs = allPrsIndex
					if allPrsIndex != RepoDisplayPolicy.Hide.rawValue {
						r.resetSyncState()
					}
				}
			} else {
				allIssuesIndex = indexPath.row
				for r in Repo.allItemsOfType("Repo", inMoc: mainObjectContext) as! [Repo] {
					r.displayPolicyForIssues = allIssuesIndex
					if allIssuesIndex != RepoDisplayPolicy.Hide.rawValue {
						r.resetSyncState()
					}
				}
			}
		} else if indexPath.section == 0 {
			repo?.displayPolicyForPrs = indexPath.row
			if indexPath.row != RepoDisplayPolicy.Hide.rawValue {
				repo?.resetSyncState()
			}
		} else {
			repo?.displayPolicyForIssues = indexPath.row
			if indexPath.row != RepoDisplayPolicy.Hide.rawValue {
				repo?.resetSyncState()
			}
		}
		tableView.reloadData()
		app.preferencesDirty = true
		DataManager.saveDB()
		settingsChangedTimer.push()
	}
}
