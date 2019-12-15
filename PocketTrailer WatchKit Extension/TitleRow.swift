
import WatchKit

final class TitleRow: NSObject, PopulatableRow {
    var label: String?
    var prRelated = false
    
	func populate(from other: Any) {
		if let o = other as? TitleRow {
            prIcon.setHidden(!o.prRelated)
            issueIcon.setHidden(o.prRelated)
            if let l = o.label, !l.isEmpty {
                titleL.setText(l)
            } else {
                titleL.setText(o.prRelated ? "PRs" : "Issues")
            }
		}
	}
    	
    @IBOutlet private weak var titleL: WKInterfaceLabel!
    @IBOutlet private weak var prIcon: WKInterfaceImage!
    @IBOutlet private weak var issueIcon: WKInterfaceImage!
}
