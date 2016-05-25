
import WatchKit

protocol PopulatableRow {
	func populateFrom(other: PopulatableRow)
	func rowType() -> String
}

final class SectionRow: NSObject, PopulatableRow {

	var section: Section?
	var totalCount: Int?
	var unreadCount: Int?
	var type: String?
	func populateFrom(other: PopulatableRow) {
		if let other = other as? SectionRow {
			if let sectionName = other.section?.watchMenuName() {
				titleL.setText("\(other.totalCount!) \(sectionName)")
			} else {
				titleL.setText("All Unread")
			}
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
