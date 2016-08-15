
import WatchKit

final class TitleRow: NSObject, PopulatableRow {
	var title: String?
	func populate(from other: AnyObject) {
		if let o = other as? TitleRow {
			titleL.setText(o.title)
		}
	}
	var rowType: String {
		return typeName(self.dynamicType)
	}
	
	@IBOutlet weak var titleL: WKInterfaceLabel!
}
