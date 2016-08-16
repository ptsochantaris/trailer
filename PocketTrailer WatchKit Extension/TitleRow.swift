
import WatchKit

final class TitleRow: NSObject, PopulatableRow {
	var title: String?
	func populate(from other: Any) {
		if let o = other as? TitleRow {
			titleL.setText(o.title)
		}
	}
	var rowType: String {
		return typeName(type(of: self))
	}
	
	@IBOutlet weak var titleL: WKInterfaceLabel!
}
