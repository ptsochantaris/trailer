
import WatchKit

protocol PopulatableRow : AnyObject {
	func populateFrom(_ other: AnyObject)
	var rowType: String { get }
}

final class SectionRow: NSObject, PopulatableRow {

	var section: Section?
	var totalCount: Int?
	var unreadCount: Int?
	var type: String?
	var groupLabel: String?
	var apiServerUri: String?

	func populateFrom(_ other: AnyObject) {
		if let other = other as? SectionRow {
			if let sectionName = other.section?.watchMenuName {
				titleL.setText("\(other.totalCount!) \(sectionName)")
			} else {
				titleL.setText("All Unread")
			}
			groupLabel = other.groupLabel
			apiServerUri = other.apiServerUri
			countL.setText("\(other.unreadCount!)")
			countHolder.setHidden(other.unreadCount==0)
		}
	}
	var rowType: String {
		return NSStringFromClass(self.dynamicType).components(separatedBy: ".").last!
	}

    @IBOutlet weak var titleL: WKInterfaceLabel!
    @IBOutlet weak var countL: WKInterfaceLabel!
    @IBOutlet weak var countHolder: WKInterfaceGroup!
	@IBOutlet weak var group: WKInterfaceGroup!
}
