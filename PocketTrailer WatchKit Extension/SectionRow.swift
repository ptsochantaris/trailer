import WatchKit

protocol PopulatableRow {
    func populate(from other: Any)
}

final class SectionRow: NSObject, PopulatableRow {
    var section: Section?
    var totalCount: Int?
    var unreadCount: Int?
    var type: String?
    var groupLabel: String?
    var apiServerUri: String?

    func populate(from other: Any) {
        if let other = other as? SectionRow {
            if let sectionName = other.section?.watchMenuName {
                titleL.setText("\(other.totalCount!) \(sectionName)")
            } else {
                titleL.setText("All Unread")
            }
            groupLabel = other.groupLabel
            apiServerUri = other.apiServerUri

            if let unread = other.unreadCount, unread > 0 {
                countL.setText(String(unread))
                countHolder.setHidden(false)
            } else {
                countHolder.setHidden(true)
            }
        }
    }

    @IBOutlet private var titleL: WKInterfaceLabel!
    @IBOutlet private var countL: WKInterfaceLabel!
    @IBOutlet private var countHolder: WKInterfaceGroup!
    @IBOutlet private var group: WKInterfaceGroup!
}
