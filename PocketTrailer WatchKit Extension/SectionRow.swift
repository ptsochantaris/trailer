
import WatchKit

protocol PopulatableRow {
	func populateFrom(other: PopulatableRow)
	func rowType() -> String
}

final class SectionRow: NSObject, PopulatableRow {

	var section: PullRequestSection?
	var totalCount: Int?
	var unreadCount: Int?
	var type: String?
	func populateFrom(other: PopulatableRow) {
		if let other = other as? SectionRow {
			titleL.setText("\(other.totalCount!) \((other.section?.watchMenuName().uppercaseString)!)")
			countL.setText("\(other.unreadCount!)")
			countHolder.setHidden(other.unreadCount==0)
		}
	}
	func rowType() -> String {
		return NSStringFromClass(self.dynamicType).componentsSeparatedByString(".").last!
	}

    @IBOutlet weak var titleL: WKInterfaceLabel!
    @IBOutlet weak var countL: WKInterfaceLabel!
    @IBOutlet weak var countHolder: WKInterfaceGroup!
	@IBOutlet weak var group: WKInterfaceGroup!
}
