import WatchKit

final class UpdatedRow: NSObject, PopulatableRow {
    var label: String?

    func populate(from other: Any) {
        updatedLabel.setText((other as? UpdatedRow)?.label)
    }

    @IBOutlet private var updatedLabel: WKInterfaceLabel!
}
