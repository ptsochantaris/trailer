import UIKit

final class RepoSettingsViewController: UITableViewController, UITextFieldDelegate {
    var repo: Repo?
    var filter: String?

    private var allPrsIndex = -1
    private var allIssuesIndex = -1
    private var allHidingIndex = -1

    @IBOutlet private var groupField: UITextField!
    @IBOutlet private var repoNameTitle: UILabel!
    @IBOutlet private var header: UIView!

    private var settingsChangedTimer: PopTimer!

    override func viewDidLoad() {
        super.viewDidLoad()

        if let repo {
            repoNameTitle.text = repo.fullName
            groupField.text = repo.groupLabel
        } else {
            if let filter {
                repoNameTitle.text = "Settings for repos matching '\(filter)' (You don't need to pick values for each setting, you can set only one setting if you prefer)"
            } else {
                repoNameTitle.text = "All repo settings (You don't need to pick values for each setting, you can set only one setting if you prefer)"
            }
            groupField.isHidden = true
        }

        settingsChangedTimer = PopTimer(timeInterval: 1.0) {
            Task {
                await DataManager.postProcessAllItems(in: DataManager.main)
            }
        }

        tableView.tableHeaderView = header
    }

    override func viewDidLayoutSubviews() {
        if let s = tableView.tableHeaderView?.systemLayoutSizeFitting(CGSize(width: tableView.bounds.size.width, height: 500)) {
            tableView.tableHeaderView?.frame = CGRect(x: 0, y: 0, width: tableView.bounds.size.width, height: s.height)
        }
        super.viewDidLayoutSubviews()
    }

    override func numberOfSections(in _: UITableView) -> Int {
        3
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 2 {
            return RepoHidingPolicy.labels.count
        }
        return RepoDisplayPolicy.allCases.filter(\.selectable).count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell")!
        if let repo {
            switch indexPath.section {
            case 0:
                let special = (indexPath.row == 0 && repo.displayPolicyForPrs == RepoDisplayPolicy.authoredOnly.rawValue)
                cell.accessoryType = (special || Int(repo.displayPolicyForPrs) == indexPath.row) ? .checkmark : .none
                let name = special ? RepoDisplayPolicy.authoredOnly.name : RepoDisplayPolicy.labels[indexPath.row]
                cell.textLabel?.text = name
                cell.textLabel?.textColor = RepoDisplayPolicy(rawValue: indexPath.row)?.color
            case 1:
                let special = (indexPath.row == 0 && repo.displayPolicyForIssues == RepoDisplayPolicy.authoredOnly.rawValue)
                cell.accessoryType = (special || Int(repo.displayPolicyForIssues) == indexPath.row) ? .checkmark : .none
                let name = special ? RepoDisplayPolicy.authoredOnly.name : RepoDisplayPolicy.labels[indexPath.row]
                cell.textLabel?.text = name
                cell.textLabel?.textColor = RepoDisplayPolicy(rawValue: indexPath.row)?.color
            case 2:
                cell.accessoryType = (Int(repo.itemHidingPolicy) == indexPath.row) ? .checkmark : .none
                cell.textLabel?.text = RepoHidingPolicy.labels[indexPath.row]
                cell.textLabel?.textColor = RepoHidingPolicy.colors[indexPath.row]
            default: break
            }
        } else {
            switch indexPath.section {
            case 0:
                cell.accessoryType = (allPrsIndex == indexPath.row) ? .checkmark : .none
                cell.textLabel?.text = RepoDisplayPolicy.labels[indexPath.row]
                cell.textLabel?.textColor = RepoDisplayPolicy(rawValue: indexPath.row)?.color
            case 1:
                cell.accessoryType = (allIssuesIndex == indexPath.row) ? .checkmark : .none
                cell.textLabel?.text = RepoDisplayPolicy.labels[indexPath.row]
                cell.textLabel?.textColor = RepoDisplayPolicy(rawValue: indexPath.row)?.color
            case 2:
                cell.accessoryType = (allHidingIndex == indexPath.row) ? .checkmark : .none
                cell.textLabel?.text = RepoHidingPolicy.labels[indexPath.row]
                cell.textLabel?.textColor = RepoHidingPolicy.colors[indexPath.row]
            default: break
            }
        }
        cell.selectionStyle = cell.accessoryType == .checkmark ? .none : .default
        return cell
    }

    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Pull Request Sections"
        case 1: return "Issue Sections"
        case 2: return "Author Based Hiding"
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if repo == nil {
            let repos: [Repo]
            if let filter {
                repos = Repo.allItems(in: DataManager.main).filter { $0.fullName?.localizedStandardContains(filter) ?? false }
            } else {
                repos = Repo.allItems(in: DataManager.main)
            }
            if indexPath.section == 0 {
                allPrsIndex = indexPath.row
                for r in repos {
                    r.displayPolicyForPrs = allPrsIndex
                    if allPrsIndex != RepoDisplayPolicy.hide.intValue {
                        r.resetSyncState()
                    }
                }
            } else if indexPath.section == 1 {
                allIssuesIndex = indexPath.row
                for r in repos {
                    r.displayPolicyForIssues = allIssuesIndex
                    if allIssuesIndex != RepoDisplayPolicy.hide.intValue {
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
            if indexPath.row != RepoDisplayPolicy.hide.intValue {
                repo?.resetSyncState()
            }
        } else if indexPath.section == 1 {
            repo?.displayPolicyForIssues = indexPath.row
            if indexPath.row != RepoDisplayPolicy.hide.intValue {
                repo?.resetSyncState()
            }
        } else {
            repo?.itemHidingPolicy = indexPath.row
        }
        tableView.reloadData()
        commit()
    }

    private func commit() {
        preferencesDirty = true
        Task {
            await DataManager.saveDB()
            settingsChangedTimer.push()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let newText = (groupField.text?.isEmpty ?? true) ? nil : groupField.text
        if let r = repo, r.groupLabel != newText {
            r.groupLabel = newText
            commit()
            Task { @MainActor in
                popupManager.masterController.updateStatus(becauseOfChanges: true)
            }
        }
        if settingsChangedTimer.isPushed {
            settingsChangedTimer.abort()
            Task {
                await DataManager.postProcessAllItems(in: DataManager.main)
            }
        }
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn _: NSRange, replacementString string: String) -> Bool {
        if string == "\n" {
            textField.resignFirstResponder()
            return false
        }
        return true
    }
}
