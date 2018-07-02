
import WatchKit

class SummaryRow: NSObject, PopulatableRow {

	@IBOutlet private weak var totalCount: WKInterfaceLabel!
	@IBOutlet private weak var totalGroup: WKInterfaceGroup!

	@IBOutlet private weak var myCount: WKInterfaceLabel!
	@IBOutlet private weak var myGroup: WKInterfaceGroup!

	@IBOutlet private weak var mentionedCount: WKInterfaceLabel!
	@IBOutlet private weak var mentionedGroup: WKInterfaceGroup!

	@IBOutlet private weak var participatedCount: WKInterfaceLabel!
	@IBOutlet private weak var participatedGroup: WKInterfaceGroup!

	@IBOutlet private weak var otherCount: WKInterfaceLabel!
	@IBOutlet private weak var otherGroup: WKInterfaceGroup!

	@IBOutlet private weak var snoozingCount: WKInterfaceLabel!
	@IBOutlet private weak var snoozingGroup: WKInterfaceGroup!

	@IBOutlet private weak var unreadCount: WKInterfaceLabel!
	@IBOutlet private weak var unreadGroup: WKInterfaceGroup!

	@IBOutlet private weak var lastUpdate: WKInterfaceLabel!

	@IBOutlet private weak var prIcon: WKInterfaceImage!
	@IBOutlet private weak var issueIcon: WKInterfaceImage!

	var rowType: String {
		return String(describing: type(of: self))
	}
	
	var data: [AnyHashable : Any]?

	func populate(from other: Any) {
		if let d = other as? SummaryRow {
			updateUI(from: d.data!)
		}
	}

	func setSummary(from result: [AnyHashable : Any]) -> Bool {
		data = result
		if let lastRefresh = result["lastUpdated"] as? Date, lastRefresh != .distantPast {
			return true
		} else {
			return false
		}
	}

	func updateUI(from result: [AnyHashable : Any]) {
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
		for r in result["views"] as! [[AnyHashable : Any]] {
			if let v = r[showIssues ? "issues" : "prs"] as? [AnyHashable : Any] {
				totalMine += (v[Section.mine.apiName] as? [AnyHashable : Any])?["total"] as? Int ?? 0
				totalParticipated += (v[Section.participated.apiName] as? [AnyHashable : Any])?["total"] as? Int ?? 0
				totalMentioned += (v[Section.mentioned.apiName] as? [AnyHashable : Any])?["total"] as? Int ?? 0
				totalSnoozed += (v[Section.snoozed.apiName] as? [AnyHashable : Any])?["total"] as? Int ?? 0
				totalOther += (v[Section.all.apiName] as? [AnyHashable : Any])?["total"] as? Int ?? 0
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

		lastUpdate.setText(agoFormat(prefix: "updated", since: result["lastUpdated"] as? Date).capitalized)
	}
}
