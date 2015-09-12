import ClockKit
import WatchConnectivity

final class ComplicationDataSource: NSObject, CLKComplicationDataSource {

	var firstUpdateDone = false

	func getNextRequestedUpdateDateWithHandler(handler: (NSDate?) -> Void) {
		handler(firstUpdateDone ? nil : NSDate())
		firstUpdateDone = true
	}

	func getPlaceholderTemplateForComplication(complication: CLKComplication, withHandler handler: (CLKComplicationTemplate?) -> Void) {

		let issues = true // TODO pick from host app
		handler(constructTemplateFor(complication, issues: issues, prCount: nil, issueCount: nil, commentCount: nil))
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

		let session = WCSession.defaultSession()
		if let overview = session.applicationContext["overview"] as? [String : AnyObject] {

			let preferIssues = overview["preferIssues"] as! Bool

			let prs = overview["prs"] as! [String : AnyObject]
			let prCount = prs["total"] as! Int

			let issues = overview["issues"] as! [String : AnyObject]
			let issueCount = issues["total"] as! Int

			let commentCount = preferIssues ? (prs["unread"] as! Int) : (issues["unread"] as! Int)
			let entry = CLKComplicationTimelineEntry(date: NSDate(), complicationTemplate: constructTemplateFor(complication, issues: preferIssues, prCount: prCount, issueCount: issueCount, commentCount: commentCount))
			handler([entry])
		} else {
			handler(nil)
		}
	}

	func getTimelineEntriesForComplication(complication: CLKComplication, afterDate date: NSDate, limit: Int, withHandler handler: ([CLKComplicationTimelineEntry]?) -> Void) {
		handler(nil)
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

	private func constructTemplateFor(complication: CLKComplication, issues: Bool, prCount: Int?, issueCount: Int?, commentCount: Int?) -> CLKComplicationTemplate {

		let prCountText = prCount == nil ? "--" : "\(prCount!)"
		let issueCountText = issueCount == nil ? "--" : "\(issueCount!)"
		let commentCountText = commentCount == nil ? "--" : "\(commentCount!)"
		let image = UIImage(named: issues ? "ComplicationIssues" : "ComplicationPrs")!

		switch complication.family {
		case .ModularSmall:
			let t = CLKComplicationTemplateModularSmallStackImage()
			t.line1ImageProvider = CLKImageProvider(onePieceImage: image)
			t.line2TextProvider = CLKSimpleTextProvider(text: issues ? issueCountText : prCountText)
			return t
		case .ModularLarge:
			let t = CLKComplicationTemplateModularLargeStandardBody()
			t.headerImageProvider = CLKImageProvider(onePieceImage: image)
			t.headerTextProvider = CLKSimpleTextProvider(text: commentCountText + " Comments")
			t.body1TextProvider = CLKSimpleTextProvider(text: prCountText + " Pull Requests", shortText: prCountText + " PRs", accessibilityLabel: prCountText + " Pull Requests")
			t.body2TextProvider = CLKSimpleTextProvider(text: issueCountText + " Issues", shortText: issueCountText + " Issues", accessibilityLabel: issueCountText + " Issues")
			return t
		case .UtilitarianSmall:
			let t = CLKComplicationTemplateUtilitarianSmallFlat()
			t.imageProvider = CLKImageProvider(onePieceImage: image)
			t.textProvider = CLKSimpleTextProvider(text: issues ? issueCountText : prCountText)
			return t
		case .UtilitarianLarge:
			let t = CLKComplicationTemplateUtilitarianLargeFlat()
			if issues {
				t.textProvider = CLKSimpleTextProvider(text: issueCountText + " Issues", shortText: issueCountText + " Issues", accessibilityLabel: issueCountText + " Issues")
			} else {
				t.textProvider = CLKSimpleTextProvider(text: prCountText + " Pull Requests", shortText: prCountText + " PRs", accessibilityLabel: prCountText + " Pull Requests")
			}
			t.imageProvider = CLKImageProvider(onePieceImage: image)
			return t
		case .CircularSmall:
			let t = CLKComplicationTemplateCircularSmallStackImage()
			t.line1ImageProvider = CLKImageProvider(onePieceImage: image)
			t.line2TextProvider = CLKSimpleTextProvider(text: issues ? issueCountText : prCountText)
			return t
		}
	}
}
