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
    }

	override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
		return 2
	}

	override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return RepoDisplayPolicy.labels.count
	}

	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier("Cell") as! UITableViewCell
		if indexPath.section == 0 {
			cell.accessoryType = (repo?.displayPolicyForPrs?.integerValue==indexPath.row) ? UITableViewCellAccessoryType.Checkmark : UITableViewCellAccessoryType.None
		} else {
			cell.accessoryType = (repo?.displayPolicyForIssues?.integerValue==indexPath.row) ? UITableViewCellAccessoryType.Checkmark : UITableViewCellAccessoryType.None
		}
		cell.textLabel?.text = RepoDisplayPolicy.labels[indexPath.row]
		return cell
	}

	override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		return section==0 ? "Pull Requests" : "Issues"
	}

	override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
		if indexPath.section == 0 {
			repo?.displayPolicyForPrs = indexPath.row
		} else {
			repo?.displayPolicyForIssues = indexPath.row
		}
		tableView.reloadData()
		if indexPath.row > 0 {
			repo?.resetSyncState()
		}
		app.preferencesDirty = true
		DataManager.saveDB()
		settingsChangedTimer.push()
	}
}
