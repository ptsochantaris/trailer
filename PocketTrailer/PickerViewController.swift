
import UIKit

protocol PickerViewControllerDelegate: class {
	func pickerViewController(picker: PickerViewController, didSelectIndexPath: IndexPath)
}

final class PickerViewController: UITableViewController {

	var values: [String]!
	weak var delegate: PickerViewControllerDelegate!
	var previousValue: Int?

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return values.count
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) 
		cell.textLabel?.text = values[indexPath.row]
		cell.accessoryType = indexPath.row == previousValue ? .checkmark : .none
		return cell
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		view.isUserInteractionEnabled = false
		previousValue = indexPath.row
		tableView.reloadData()

		atNextEvent(self) { S in
			_ = S.navigationController?.popViewController(animated: true)
			S.delegate.pickerViewController(picker: S, didSelectIndexPath: indexPath)
		}
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		return "Please select an option"
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		navigationItem.largeTitleDisplayMode = .automatic
	}

	private var layoutDone = false

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		if !layoutDone {
			if let p = previousValue {
				tableView.scrollToRow(at: IndexPath(row: p, section: 0), at: .middle, animated: false)
			}
			layoutDone = true
		}
	}
}
