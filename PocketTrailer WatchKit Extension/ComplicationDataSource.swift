import ClockKit
import WatchConnectivity

final class ComplicationDataSource: NSObject, CLKComplicationDataSource {

	func getNextRequestedUpdateDate(handler: @escaping (Date?) -> Void) {
		handler(nil)
	}

	func getPlaceholderTemplate(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTemplate?) -> Void) {
		handler(constructTemplate(for: complication, issues: false, prCount: nil, issueCount: nil, commentCount: 0))
	}

	func getPrivacyBehavior(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void) {
		handler(CLKComplicationPrivacyBehavior.showOnLockScreen)
	}

	func getCurrentTimelineEntry(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void) {
		getTimelineEntries(for: complication, before: Date(), limit: 1) { entries in
			handler(entries?.first)
		}
	}

	func getTimelineEntries(for complication: CLKComplication, before date: Date, limit: Int, withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void) {
		entriesFor(complication, handler)
	}

	func getTimelineEntries(for complication: CLKComplication, after date: Date, limit: Int, withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void) {
		entriesFor(complication, handler)
	}

	private func entriesFor(_ complication: CLKComplication, _ handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void) {
		if let overview = WCSession.default().receivedApplicationContext["overview"] as? [AnyHashable : Any] {
			processOverview(for: complication, overview, handler)
		} else {
			handler(nil)
		}
	}

	private func processOverview(for complication: CLKComplication, _ overview: [AnyHashable : Any], _ handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void) {

		let showIssues = overview["preferIssues"] as! Bool

		var prCount = 0
		var issueCount = 0
		var commentCount = 0
		for r in overview["views"] as? [[AnyHashable : Any]] ?? [] {
			if let v = r["prs"] as? [AnyHashable : Any] {
				prCount += v["total_open"] as? Int ?? 0
				commentCount += v["unread"] as? Int ?? 0
			}
			if let v = r["issues"] as? [AnyHashable : Any] {
				issueCount += v["total_open"] as? Int ?? 0
				commentCount += v["unread"] as? Int ?? 0
			}
		}

		let entry = CLKComplicationTimelineEntry(date: Date(), complicationTemplate: constructTemplate(for: complication, issues: showIssues, prCount: prCount, issueCount: issueCount, commentCount: commentCount))
		handler([entry])
	}

	func getSupportedTimeTravelDirections(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimeTravelDirections) -> Void) {
		handler([])
	}

	func getTimelineStartDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
		handler(Date())
	}

	func getTimelineEndDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
		handler(Date())
	}

	private func count(_ count: Int?, unit: String?) -> String {
		if let u = unit {
			if let c = count {
				if c == 0 {
					return "No \(u)s"
				} else if c > 1 {
					return "\(c) \(u)s"
				} else {
					return "1 \(u)"
				}
			} else {
				return "-- \(u)s"
			}
		} else {
			if let c = count {
				return "\(c)"
			} else {
				return "--"
			}
		}
	}

	private func constructTemplate(for complication: CLKComplication, issues: Bool, prCount: Int?, issueCount: Int?, commentCount: Int) -> CLKComplicationTemplate {

		switch complication.family {
		case .modularSmall:
			let t = CLKComplicationTemplateModularSmallStackImage()
			t.line1ImageProvider = CLKImageProvider(onePieceImage: UIImage(named: issues ? "ComplicationIssues" : "ComplicationPrs")!)
			t.line2TextProvider = CLKSimpleTextProvider(text: count(issues ? issueCount : prCount, unit: nil))
			return t
		case .modularLarge:
			let t = CLKComplicationTemplateModularLargeStandardBody()
			t.headerImageProvider = CLKImageProvider(onePieceImage: UIImage(named: "ComplicationPrs")!)
			t.headerTextProvider = CLKSimpleTextProvider(text: count(commentCount, unit: "Comment"))
			t.body1TextProvider = CLKSimpleTextProvider(text: count(prCount, unit: "Pull Request"))
			t.body2TextProvider = CLKSimpleTextProvider(text: count(issueCount, unit: "Issue"))
			return t
		case .extraLarge:
			let t = CLKComplicationTemplateExtraLargeColumnsText()
			t.row1Column2TextProvider = CLKSimpleTextProvider(text: "\(issues ? (issueCount ?? 0) : (prCount ?? 0))")
			t.row1Column1TextProvider = CLKSimpleTextProvider(text: issues ? "Iss" : "PRs")
			t.row2Column2TextProvider = CLKSimpleTextProvider(text: commentCount == 0 ? "-" : "\(commentCount)")
			t.row2Column1TextProvider = CLKSimpleTextProvider(text: "Com")
			t.column2Alignment = .trailing
			t.highlightColumn2 = commentCount > 0
			return t
 		case .utilitarianSmallFlat, .utilitarianSmall:
			let t = CLKComplicationTemplateUtilitarianSmallFlat()
			t.imageProvider = CLKImageProvider(onePieceImage: UIImage(named: issues ? "ComplicationIssues" : "ComplicationPrs")!)
			t.textProvider = CLKSimpleTextProvider(text: count(issues ? issueCount : prCount, unit: nil))
			return t
		case .utilitarianLarge:
			let t = CLKComplicationTemplateUtilitarianLargeFlat()
			if commentCount > 0 {
				t.textProvider = CLKSimpleTextProvider(text: count(commentCount, unit: "New Comment"))
			} else if issues {
				t.imageProvider = CLKImageProvider(onePieceImage: UIImage(named: "ComplicationIssues")!)
				t.textProvider = CLKSimpleTextProvider(text: count(issueCount, unit: "Issue"))
			} else {
				t.imageProvider = CLKImageProvider(onePieceImage: UIImage(named: "ComplicationPrs")!)
				t.textProvider = CLKSimpleTextProvider(text: count(prCount, unit: "Pull Request"))
			}
			return t
		case .circularSmall:
			let t = CLKComplicationTemplateCircularSmallStackImage()
			t.line1ImageProvider = CLKImageProvider(onePieceImage: UIImage(named: issues ? "ComplicationIssues" : "ComplicationPrs")!)
			t.line2TextProvider = CLKSimpleTextProvider(text: count(issues ? issueCount : prCount, unit: nil))
			return t
		}
	}
}
