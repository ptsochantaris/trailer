
import WatchKit

class SummaryRow: NSObject, PopulatableRow {

	@IBOutlet weak var totalCount: WKInterfaceLabel!
	@IBOutlet var totalGroup: WKInterfaceGroup!

	@IBOutlet weak var myCount: WKInterfaceLabel!
	@IBOutlet weak var myGroup: WKInterfaceGroup!

	@IBOutlet weak var mentionedCount: WKInterfaceLabel!
	@IBOutlet weak var mentionedGroup: WKInterfaceGroup!

	@IBOutlet weak var participatedCount: WKInterfaceLabel!
	@IBOutlet weak var participatedGroup: WKInterfaceGroup!

	@IBOutlet weak var otherCount: WKInterfaceLabel!
	@IBOutlet weak var otherGroup: WKInterfaceGroup!

	@IBOutlet weak var snoozingCount: WKInterfaceLabel!
	@IBOutlet weak var snoozingGroup: WKInterfaceGroup!

	@IBOutlet weak var unreadCount: WKInterfaceLabel!
	@IBOutlet weak var unreadGroup: WKInterfaceGroup!

	@IBOutlet weak var lastUpdate: WKInterfaceLabel!

	@IBOutlet weak var prIcon: WKInterfaceImage!
	@IBOutlet weak var issueIcon: WKInterfaceImage!

	var rowType: String {
		return NSStringFromClass(self.dynamicType).components(separatedBy: ".").last!
	}
	
	var data: [String : AnyObject]?

	func populateFrom(_ other: AnyObject) {
		if let d = other as? SummaryRow {
			updateUI(d.data!)
		}
	}

	func setSummary(_ result: [String : AnyObject]) -> Bool {
		data = result
		if let lastRefresh = result["lastUpdated"] as? Date, lastRefresh != Date.distantPast {
			return true
		} else {
			return false
		}
	}

	func updateUI(_ result: [String : AnyObject]) {
		let showIssues = result["preferIssues"] as! Bool
		prIcon.setHidden(showIssues)
		issueIcon.setHidden(!showIssues)

		var totalOpen = 0
		var totalUnread = 0
		var totalMine = 0
		var totalParticipated = 0
		var totalMentioned = 0
		var totalSnoozed = 0
		var totalOther = 0
		for r in result["views"] as! [[String : AnyObject]] {
			if let v = r[showIssues ? "issues" : "prs"] as? [String : AnyObject] {
				totalMine += v[Section.mine.apiName]?["total"] as? Int ?? 0
				totalParticipated += v[Section.participated.apiName]?["total"] as? Int ?? 0
				totalMentioned += v[Section.mentioned.apiName]?["total"] as? Int ?? 0
				totalSnoozed += v[Section.snoozed.apiName]?["total"] as? Int ?? 0
				totalOther += v[Section.all.apiName]?["total"] as? Int ?? 0
				totalUnread += v["unread"] as? Int ?? 0
				totalOpen += v["total_open"] as? Int ?? 0
			}
		}

		totalCount.setText("\(totalOpen)")

		func setCount(_ c: Int, section: Section, _ count: WKInterfaceLabel, _ group: WKInterfaceGroup) {
			count.setText("\(c) \(section.watchMenuName.uppercased())")
			group.setAlpha(c==0 ? 0.4 : 1.0)
		}
		setCount(totalMine, section: .mine, myCount, myGroup)
		setCount(totalParticipated, section: .participated, participatedCount, participatedGroup)
		setCount(totalMentioned, section: .mentioned, mentionedCount, mentionedGroup)
		setCount(totalOther, section: .all, otherCount, otherGroup)
		setCount(totalSnoozed, section: .snoozed, snoozingCount, snoozingGroup)

		if totalUnread==0 {
			unreadCount.setText("NONE UNREAD")
			unreadGroup.setAlpha(0.3)
		} else if totalUnread==1 {
			unreadCount.setText("1 COMMENT")
			unreadGroup.setAlpha(1.0)
		} else {
			unreadCount.setText("\(totalUnread) COMMENTS")
			unreadGroup.setAlpha(1.0)
		}

		if let lastRefresh = result["lastUpdated"] as? Date, lastRefresh != Date.distantPast {
			lastUpdate.setText(shortDateFormatter.string(from: lastRefresh))
		} else {
			lastUpdate.setText("Not refreshed yet")
		}
	}
}
