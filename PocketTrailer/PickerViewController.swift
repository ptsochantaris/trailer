import UIKit

protocol PickerViewControllerDelegate: AnyObject {
    func pickerViewController(picker: PickerViewController, didSelectIndexPath: IndexPath, info: PickerViewController.Info)
}

final class PickerViewController: UITableViewController {
    struct Info {
        let title: String
        let values: [String]
        let selectedIndex: Int?
        let sourceIndexPath: IndexPath
    }

    var info: Info! {
        didSet {
            previousValue = info.selectedIndex
            title = info.title
        }
    }

    weak var delegate: PickerViewControllerDelegate?
    private var previousValue: Int?

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        info.values.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.textLabel?.text = info.values[indexPath.row]
        cell.accessoryType = indexPath.row == previousValue ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        view.isUserInteractionEnabled = false
        previousValue = indexPath.row
        tableView.reloadData()

        Task { @MainActor in
            _ = navigationController?.popViewController(animated: true)
            delegate?.pickerViewController(picker: self, didSelectIndexPath: indexPath, info: info)
        }
    }

    override func tableView(_: UITableView, titleForHeaderInSection _: Int) -> String? {
        "Please select an option"
    }

    private var layoutDone = false

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !layoutDone {
            if let previousValue {
                tableView.scrollToRow(at: IndexPath(row: previousValue, section: 0), at: .middle, animated: false)
            }
            layoutDone = true
        }
    }
}
