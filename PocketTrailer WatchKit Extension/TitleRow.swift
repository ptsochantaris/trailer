
import WatchKit

final class TitleRow: NSObject, PopulatableRow {
	var title: String?
	func populateFrom(_ other: PopulatableRow) {
		if let other = other as? TitleRow {
			titleL.setText(other.title)
		}
	}
	func rowType() -> String {
		return NSStringFromClass(self.dynamicType).components(separatedBy: ".").last!
	}
	
	@IBOutlet weak var titleL: WKInterfaceLabel!
}
