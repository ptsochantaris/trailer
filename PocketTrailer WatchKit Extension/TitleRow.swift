
import WatchKit

final class TitleRow: NSObject, PopulatableRow {
	var title: String?
	func populateFrom(_ other: AnyObject) {
		if let o = other as? TitleRow {
			titleL.setText(o.title)
		}
	}
	var rowType: String {
		return NSStringFromClass(self.dynamicType).components(separatedBy: ".").last!
	}
	
	@IBOutlet weak var titleL: WKInterfaceLabel!
}
