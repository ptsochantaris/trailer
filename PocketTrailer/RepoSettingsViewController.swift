import UIKit

final class RepoSettingsViewController: UITableViewController, UITextFieldDelegate {

	var repo: Repo?

	private var allPrsIndex: Int = -1
	private var allIssuesIndex: Int = -1
	private var allHidingIndex: Int = -1

	@IBOutlet weak var groupField: UITextField!
	@IBOutlet weak var repoNameTitle: UILabel!

	private var settingsChangedTimer: PopTimer!

	override func viewDidLoad() {
		super.viewDidLoad()
		if repo == nil {
			repoNameTitle.text = "All Repositories (You don't need to pick values for every group below, you can set only a specific group if you prefer)"
			tableView.tableFooterView = nil
		} else {
			repoNameTitle.text = repo?.fullName
			groupField.text = repo?.groupLabel
		}
		settingsChangedTimer = PopTimer(timeInterval: 1.0) {
			DataManager.postProcessAllItems()
			DataManager.saveDB()
		}
	}

	override func viewDidLayoutSubviews() {
		if let s = tableView.tableHeaderView?.systemLayoutSizeFittingSize(CGSizeMake(tableView.bounds.size.width, 500)) {
			tableView.tableHeaderView?.frame = CGRectMake(0, 0, tableView.bounds.size.width, s.height)
		}
		super.viewDidLayoutSubviews()
	}

	override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
		return 3
	}

	override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if section == 2 {
			return RepoHidingPolicy.labels.count
		}
		return RepoDisplayPolicy.labels.count
	}

	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier("Cell")!
		if repo == nil {
			switch indexPath.section {
			case 0:
				cell.accessoryType = (allPrsIndex==indexPath.row) ? .Checkmark : .None
				cell.textLabel?.text = RepoDisplayPolicy.labels[indexPath.row]
				cell.textLabel?.textColor = RepoDisplayPolicy.colors[indexPath.row]
			case 1:
				cell.accessoryType = (allIssuesIndex==indexPath.row) ? .Checkmark : .None
				cell.textLabel?.text = RepoDisplayPolicy.labels[indexPath.row]
				cell.textLabel?.textColor = RepoDisplayPolicy.colors[indexPath.row]
			case 2:
				cell.accessoryType = (allHidingIndex==indexPath.row) ? .Checkmark : .None
				cell.textLabel?.text = RepoHidingPolicy.labels[indexPath.row]
				cell.textLabel?.textColor = RepoHidingPolicy.colors[indexPath.row]
			default: break
			}
		} else {
			switch indexPath.section {
			case 0:
				cell.accessoryType = ((repo?.displayPolicyForPrs?.integerValue ?? 0)==indexPath.row) ? .Checkmark : .None
				cell.textLabel?.text = RepoDisplayPolicy.labels[indexPath.row]
				cell.textLabel?.textColor = RepoDisplayPolicy.colors[indexPath.row]
			case 1:
				cell.accessoryType = ((repo?.displayPolicyForIssues?.integerValue ?? 0)==indexPath.row) ? .Checkmark : .None
				cell.textLabel?.text = RepoDisplayPolicy.labels[indexPath.row]
				cell.textLabel?.textColor = RepoDisplayPolicy.colors[indexPath.row]
			case 2:
				cell.accessoryType = ((repo?.itemHidingPolicy?.integerValue ?? 0)==indexPath.row) ? .Checkmark : .None
				cell.textLabel?.text = RepoHidingPolicy.labels[indexPath.row]
				cell.textLabel?.textColor = RepoHidingPolicy.colors[indexPath.row]
			default: break
			}
		}
		cell.selectionStyle = cell.accessoryType == .Checkmark ? .None : .Default
		return cell
	}

	override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		switch section {
		case 0: return "Pull Request Sections"
		case 1: return "Issue Sections"
		case 2: return "Author Based Hiding"
		default: return nil
		}
	}

	override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
		if repo == nil {
			let repos = Repo.allItemsOfType("Repo", inMoc: mainObjectContext) as! [Repo]
			if indexPath.section == 0 {
				allPrsIndex = indexPath.row
				for r in repos {
					r.displayPolicyForPrs = allPrsIndex
					if allPrsIndex != RepoDisplayPolicy.Hide.rawValue {
						r.resetSyncState()
					}
				}
			} else if indexPath.section == 1 {
				allIssuesIndex = indexPath.row
				for r in repos {
					r.displayPolicyForIssues = allIssuesIndex
					if allIssuesIndex != RepoDisplayPolicy.Hide.rawValue {
						r.resetSyncState()
					}
				}
			} else {
				allHidingIndex = indexPath.row
				for r in repos {
					r.itemHidingPolicy = allHidingIndex
				}
			}
		} else if indexPath.section == 0 {
			repo?.displayPolicyForPrs = indexPath.row
			if indexPath.row != RepoDisplayPolicy.Hide.rawValue {
				repo?.resetSyncState()
			}
		} else if indexPath.section == 1 {
			repo?.displayPolicyForIssues = indexPath.row
			if indexPath.row != RepoDisplayPolicy.Hide.rawValue {
				repo?.resetSyncState()
			}
		} else {
			repo?.itemHidingPolicy = indexPath.row
		}
		tableView.reloadData()
		preferencesDirty = true
		DataManager.saveDB()
		settingsChangedTimer.push()
	}

	override func viewWillDisappear(animated: Bool) {
		super.viewWillDisappear(animated)
		if groupField == nil { return }
		let newText = (groupField.text?.isEmpty ?? true) ? nil : groupField.text
		if let r = repo where r.groupLabel != newText {
			r.groupLabel = newText
			preferencesDirty = true
			DataManager.saveDB()
			settingsChangedTimer.push()
		}
	}

	func textField(textField: UITextField, shouldChangeCharactersInRange range: NSRange, replacementString string: String) -> Bool {
		if string == "\n" {
			textField.resignFirstResponder()
			return false
		}
		return true
	}
}
