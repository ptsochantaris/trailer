
import WatchKit

final class TitleRow: NSObject, PopulatableRow {
	var title: String?
	func populateFrom(other: PopulatableRow) {
		if let other = other as? TitleRow {
			titleL.setText(other.title!)
		}
	}
	func rowType() -> String {
		return NSStringFromClass(self.dynamicType).componentsSeparatedByString(".").last!
	}
	
	@IBOutlet weak var titleL: WKInterfaceLabel!
	@IBOutlet weak var group: WKInterfaceGroup!
}