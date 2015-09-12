import ClockKit
import WatchConnectivity

final class ComplicationDataSource: NSObject, CLKComplicationDataSource {

	func getNextRequestedUpdateDateWithHandler(handler: (NSDate?) -> Void) {
		handler(NSDate().dateByAddingTimeInterval(60))
	}

	func getPlaceholderTemplateForComplication(complication: CLKComplication, withHandler handler: (CLKComplicationTemplate?) -> Void) {
		handler(constructTemplateFor(complication, issues: false, prCount: nil, issueCount: nil, commentCount: nil))
	}

	func getPrivacyBehaviorForComplication(complication: CLKComplication, withHandler handler: (CLKComplicationPrivacyBehavior) -> Void) {
		handler(CLKComplicationPrivacyBehavior.ShowOnLockScreen)
	}

	func getCurrentTimelineEntryForComplication(complication: CLKComplication, withHandler handler: (CLKComplicationTimelineEntry?) -> Void) {
		getTimelineEntriesForComplication(complication, beforeDate: NSDate(), limit: 1) { entries in
			handler(entries?.first)
		}
	}

	func getTimelineEntriesForComplication(complication: CLKComplication, beforeDate date: NSDate, limit: Int, withHandler handler: ([CLKComplicationTimelineEntry]?) -> Void) {
		entriesFor(complication, handler)
	}

	func getTimelineEntriesForComplication(complication: CLKComplication, afterDate date: NSDate, limit: Int, withHandler handler: ([CLKComplicationTimelineEntry]?) -> Void) {
		entriesFor(complication, handler)
	}

	private func entriesFor(complication: CLKComplication, _ handler: ([CLKComplicationTimelineEntry]?) -> Void) {
		if let overview = WCSession.defaultSession().receivedApplicationContext["overview"] as? [String : AnyObject] {
			processOverview(complication, overview, handler)
		} else {
			handler(nil)
		}
	}

	private func processOverview(complication: CLKComplication, _ overview: [String: AnyObject], _ handler: ([CLKComplicationTimelineEntry]?) -> Void) {
		let preferIssues = overview["preferIssues"] as! Bool

		let prs = overview["prs"] as! [String : AnyObject]
		let prCount = prs["total"] as! Int

		let issues = overview["issues"] as! [String : AnyObject]
		let issueCount = issues["total"] as! Int

		let commentCount = preferIssues ? (prs["unread"] as! Int) : (issues["unread"] as! Int)
		let entry = CLKComplicationTimelineEntry(date: NSDate(), complicationTemplate: constructTemplateFor(complication, issues: preferIssues, prCount: prCount, issueCount: issueCount, commentCount: commentCount))
		handler([entry])
	}

	func getSupportedTimeTravelDirectionsForComplication(complication: CLKComplication, withHandler handler: (CLKComplicationTimeTravelDirections) -> Void) {
		handler([CLKComplicationTimeTravelDirections.None])
	}

	func getTimelineStartDateForComplication(complication: CLKComplication, withHandler handler: (NSDate?) -> Void) {
		handler(NSDate())
	}

	func getTimelineEndDateForComplication(complication: CLKComplication, withHandler handler: (NSDate?) -> Void) {
		handler(NSDate())
	}

	private func count(count: Int?, unit: String?) -> String {
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

	private func constructTemplateFor(complication: CLKComplication, issues: Bool, prCount: Int?, issueCount: Int?, commentCount: Int?) -> CLKComplicationTemplate {

		let image = UIImage(named: issues ? "ComplicationIssues" : "ComplicationPrs")!

		switch complication.family {
		case .ModularSmall:
			let t = CLKComplicationTemplateModularSmallStackImage()
			t.line1ImageProvider = CLKImageProvider(onePieceImage: image)
			t.line2TextProvider = CLKSimpleTextProvider(text: count(issues ? issueCount : prCount, unit: nil))
			return t
		case .ModularLarge:
			let t = CLKComplicationTemplateModularLargeStandardBody()
			t.headerImageProvider = CLKImageProvider(onePieceImage: image)
			t.headerTextProvider = CLKSimpleTextProvider(text: count(commentCount, unit: "Comment"))
			t.body1TextProvider = CLKSimpleTextProvider(text: count(prCount, unit: "Pull Request"))
			t.body2TextProvider = CLKSimpleTextProvider(text: count(issueCount, unit: "Issue"))
			return t
		case .UtilitarianSmall:
			let t = CLKComplicationTemplateUtilitarianSmallFlat()
			t.imageProvider = CLKImageProvider(onePieceImage: image)
			t.textProvider = CLKSimpleTextProvider(text: count(issues ? issueCount : prCount, unit: nil))
			return t
		case .UtilitarianLarge:
			let t = CLKComplicationTemplateUtilitarianLargeFlat()
			t.imageProvider = CLKImageProvider(onePieceImage: image)
			if issues {
				t.textProvider = CLKSimpleTextProvider(text: count(issueCount, unit: "Issue"))
			} else {
				t.textProvider = CLKSimpleTextProvider(text: count(prCount, unit: "Pull Request"))
			}
			return t
		case .CircularSmall:
			let t = CLKComplicationTemplateCircularSmallStackImage()
			t.line1ImageProvider = CLKImageProvider(onePieceImage: image)
			t.line2TextProvider = CLKSimpleTextProvider(text: count(issues ? issueCount : prCount, unit: nil))
			return t
		}
	}
}
