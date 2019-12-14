
import UIKit

final class WatchlistSettingsViewController: UITableViewController, PickerViewControllerDelegate {

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		updateState()
	}

	@IBOutlet private weak var rescanCell: UITableViewCell!
	@IBOutlet private weak var autoAddCell: UITableViewCell!
	@IBOutlet private weak var autoRemoveCell: UITableViewCell!
	@IBOutlet private weak var hideArchivedCell: UITableViewCell!

	override func viewDidLoad() {
		super.viewDidLoad()
		tableView.estimatedRowHeight = 100
		tableView.rowHeight = UITableView.automaticDimension
		rescanCell.detailTextLabel?.text = Settings.newRepoCheckPeriodHelp
		autoAddCell.detailTextLabel?.text = Settings.automaticallyAddNewReposFromWatchlistHelp
		autoRemoveCell.detailTextLabel?.text = Settings.automaticallyRemoveDeletedReposFromWatchlistHelp
		hideArchivedCell.detailTextLabel?.text = Settings.hideArchivedReposHelp
	}

	private func updateState() {
		rescanCell.textLabel?.text = "Re-scan every \(Int(Settings.newRepoCheckPeriod)) hours"
		autoAddCell.accessoryType = Settings.automaticallyAddNewReposFromWatchlist ? .checkmark : .none
		autoRemoveCell.accessoryType = Settings.automaticallyRemoveDeletedReposFromWatchlist ? .checkmark : .none
		hideArchivedCell.accessoryType = Settings.hideArchivedRepos ? .checkmark : .none
	}

    func pickerViewController(picker: PickerViewController, didSelectIndexPath: IndexPath, info: PickerViewController.Info) {
		Settings.newRepoCheckPeriod = Float(didSelectIndexPath.row + 2)
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		if indexPath.section == 0 {
            let values = (2 ..< 1000).map { "\($0) hours" }
            let index = Int(Settings.newRepoCheckPeriod) - 2
            let v = PickerViewController.Info(title: "Re-scan every…", values: values, selectedIndex: index, sourceIndexPath: indexPath)
			performSegue(withIdentifier: "showPicker", sender: v)
		} else {
			if indexPath.row == 0 {
				Settings.automaticallyAddNewReposFromWatchlist = !Settings.automaticallyAddNewReposFromWatchlist
			} else if indexPath.row == 1 {
				Settings.automaticallyRemoveDeletedReposFromWatchlist = !Settings.automaticallyRemoveDeletedReposFromWatchlist
			} else {
				Settings.hideArchivedRepos = !Settings.hideArchivedRepos
				if Settings.hideArchivedRepos && Repo.hideArchivedRepos(in: DataManager.main) {
					DataManager.saveDB()
					DataManager.postProcessAllItems()
				}
			}
			updateState()
		}
		tableView.deselectRow(at: indexPath, animated: true)
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let p = segue.destination as? PickerViewController, let i = sender as? PickerViewController.Info {
            p.info = i
			p.delegate = self
		}
	}
}
