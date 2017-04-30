
import UIKit

final class WatchlistSettingsViewController: UITableViewController, PickerViewControllerDelegate {

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		updateState()
	}

	@IBOutlet weak var rescanCell: UITableViewCell!
	@IBOutlet weak var autoAddCell: UITableViewCell!
	@IBOutlet weak var autoRemoveCell: UITableViewCell!

	override func viewDidLoad() {
		super.viewDidLoad()
		rescanCell.detailTextLabel?.text = Settings.newRepoCheckPeriodHelp
		autoAddCell.detailTextLabel?.text = Settings.automaticallyAddNewReposFromWatchlistHelp
		autoRemoveCell.detailTextLabel?.text = Settings.automaticallyRemoveDeletedReposFromWatchlistHelp
	}

	private func updateState() {
		rescanCell.textLabel?.text = "Re-scan every \(Int(Settings.newRepoCheckPeriod)) hours"
		autoAddCell.accessoryType = Settings.automaticallyAddNewReposFromWatchlist ? .checkmark : .none
		autoRemoveCell.accessoryType = Settings.automaticallyRemoveDeletedReposFromWatchlist ? .checkmark : .none
	}

	func pickerViewController(picker: PickerViewController, didSelectIndexPath: IndexPath) {
		Settings.newRepoCheckPeriod = Float(didSelectIndexPath.row + 2)
	}

	override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
		if indexPath.section == 0 {
			return calculateHeight(for: rescanCell)
		} else {
			if indexPath.row == 0 {
				return calculateHeight(for: autoAddCell)
			} else {
				return calculateHeight(for: autoRemoveCell)
			}
		}
	}

	private func calculateHeight(for cell: UITableViewCell) -> CGFloat {
		var h: CGFloat = 30
		cell.layoutIfNeeded()
		if let l1 = cell.textLabel {
			h += l1.frame.size.height
		}
		if let l2 = cell.detailTextLabel {
			h += l2.frame.size.height
		}
		return h
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		if indexPath.section == 0 {
			performSegue(withIdentifier: "showPicker", sender: self)
		} else {
			if indexPath.row == 0 {
				Settings.automaticallyAddNewReposFromWatchlist = !Settings.automaticallyAddNewReposFromWatchlist
			} else {
				Settings.automaticallyRemoveDeletedReposFromWatchlist = !Settings.automaticallyRemoveDeletedReposFromWatchlist
			}
			updateState()
		}
		tableView.deselectRow(at: indexPath, animated: true)
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if let p = segue.destination as? PickerViewController {
			p.title = "Re-scan every…"
			p.values = (2 ..< 1000).map { "\($0) hours" }
			p.previousValue = Int(Settings.newRepoCheckPeriod) - 2
			p.delegate = self
		}
	}
}
