
import UIKit

protocol PickerViewControllerDelegate: class {
	func pickerViewController(picker: PickerViewController, didSelectIndexPath: NSIndexPath)
}

final class PickerViewController: UITableViewController {

	var values: [String]!
	weak var delegate: PickerViewControllerDelegate!
	var previousValue: Int?

	override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
		return 1
	}

	override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return values.count
	}

	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath) 
		cell.textLabel?.text = values[indexPath.row]
		cell.accessoryType = indexPath.row == previousValue ? UITableViewCellAccessoryType.Checkmark : UITableViewCellAccessoryType.None
		return cell
	}

	override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
		view.userInteractionEnabled = false
		previousValue = indexPath.row
		tableView.reloadData()

		atNextEvent { [weak self] in
			self!.navigationController?.popViewControllerAnimated(true)
			self!.delegate.pickerViewController(self!, didSelectIndexPath: indexPath)
		}
	}

	override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		return "Please select an option"
	}

	private var layoutDone: Bool = false

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		if !layoutDone {
			if let p = previousValue {
				tableView.scrollToRowAtIndexPath(NSIndexPath(forRow: p, inSection:0), atScrollPosition: UITableViewScrollPosition.Middle, animated: false)
			}
			layoutDone = true
		}
	}
}
