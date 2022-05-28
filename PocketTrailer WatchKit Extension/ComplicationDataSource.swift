import ClockKit
import WatchConnectivity

final class ComplicationDataSource: NSObject, CLKComplicationDataSource {

	func getPlaceholderTemplate(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTemplate?) -> Void) {
		let emptyTemplate = constructTemplate(for: complication, issues: false, prCount: nil, issueCount: nil, commentCount: 0)
		handler(emptyTemplate)
	}

	func getPrivacyBehavior(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void) {
		handler(.showOnLockScreen)
	}

	func getCurrentTimelineEntry(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void) {
		entriesFor(complication) { entries in
			handler(entries?.first)
		}
	}

	private func entriesFor(_ complication: CLKComplication, _ handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void) {
        if let overview = ExtensionDelegate.storedOverview {
			processOverview(for: complication, overview, handler)
		} else {
			handler(nil)
		}
	}

	private func processOverview(for complication: CLKComplication, _ overview: [AnyHashable: Any], _ handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void) {

		let showIssues = overview["preferIssues"] as! Bool

		var prCount = 0
		var issueCount = 0
		var commentCount = 0
		for r in overview["views"] as? [[AnyHashable: Any]] ?? [] {
			if let v = r["prs"] as? [AnyHashable: Any] {
				prCount += v["total_open"] as? Int ?? 0
				commentCount += v["unread"] as? Int ?? 0
			}
			if let v = r["issues"] as? [AnyHashable: Any] {
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
            return CLKComplicationTemplateModularSmallStackImage(
                line1ImageProvider: CLKImageProvider(onePieceImage: UIImage(named: issues ? "ComplicationIssues" : "ComplicationPrs")!),
                line2TextProvider: CLKSimpleTextProvider(text: count(issues ? issueCount : prCount, unit: nil)))
            
        case .modularLarge:
            return CLKComplicationTemplateModularLargeStandardBody(
                headerImageProvider: CLKImageProvider(onePieceImage: UIImage(named: "ComplicationPrs")!),
                headerTextProvider: CLKSimpleTextProvider(text: count(commentCount, unit: "Comment")),
                body1TextProvider: CLKSimpleTextProvider(text: count(prCount, unit: "Pull Request")),
                body2TextProvider: CLKSimpleTextProvider(text: count(issueCount, unit: "Issue")))
            
        case .extraLarge:
            let t =  CLKComplicationTemplateExtraLargeColumnsText(
                row1Column1TextProvider: CLKSimpleTextProvider(text: issues ? "Iss" : "PRs"),
                row1Column2TextProvider: CLKSimpleTextProvider(text: "\(issues ? (issueCount ?? 0) : (prCount ?? 0))"),
                row2Column1TextProvider: CLKSimpleTextProvider(text: "Com"),
                row2Column2TextProvider: CLKSimpleTextProvider(text: commentCount == 0 ? "-" : "\(commentCount)"))
            t.column2Alignment = .trailing
            t.highlightColumn2 = commentCount > 0
            return t
            
        case .utilitarianSmallFlat, .utilitarianSmall:
            return CLKComplicationTemplateUtilitarianSmallFlat(
                textProvider: CLKSimpleTextProvider(text: count(issues ? issueCount : prCount, unit: nil)),
                imageProvider: CLKImageProvider(onePieceImage: UIImage(named: issues ? "ComplicationIssues" : "ComplicationPrs")!))
            
        case .utilitarianLarge:
            if commentCount > 0 {
                return CLKComplicationTemplateUtilitarianLargeFlat(textProvider: CLKSimpleTextProvider(text: count(commentCount, unit: "New Comment")))
            } else if issues {
                return CLKComplicationTemplateUtilitarianLargeFlat(textProvider: CLKSimpleTextProvider(text: count(issueCount, unit: "Issue")))
            } else {
                return CLKComplicationTemplateUtilitarianLargeFlat(textProvider: CLKSimpleTextProvider(text: count(prCount, unit: "Pull Request")))
            }
            
        case .circularSmall:
            return CLKComplicationTemplateCircularSmallStackImage(
                line1ImageProvider: CLKImageProvider(onePieceImage: UIImage(named: issues ? "ComplicationIssues" : "ComplicationPrs")!),
                line2TextProvider: CLKSimpleTextProvider(text: count(issues ? issueCount : prCount, unit: nil)))
            
        case .graphicCorner:
            if commentCount > 0 {
                let p = CLKSimpleTextProvider(text: count(commentCount, unit: "Comment"))
                p.tintColor = .red
                return CLKComplicationTemplateGraphicCornerTextImage(
                    textProvider: p,
                    imageProvider: CLKFullColorImageProvider(fullColorImage: UIImage(named: issues ? "IssuesCorner" : "PrsCorner")!))
            } else if issues {
                return CLKComplicationTemplateGraphicCornerTextImage(
                    textProvider: CLKSimpleTextProvider(text: count(issueCount, unit: "Issue")),
                    imageProvider: CLKFullColorImageProvider(fullColorImage: UIImage(named: issues ? "IssuesCorner" : "PrsCorner")!))
            } else {
                return CLKComplicationTemplateGraphicCornerTextImage(
                    textProvider: CLKSimpleTextProvider(text: count(prCount, unit: "PR")),
                    imageProvider: CLKFullColorImageProvider(fullColorImage: UIImage(named: issues ? "IssuesCorner" : "PrsCorner")!))
            }
            
        case .graphicBezel:
            let textProvider: CLKSimpleTextProvider
            if commentCount > 0 {
                textProvider = CLKSimpleTextProvider(text: count(commentCount, unit: "New Comment"))
            } else if issues {
                textProvider = CLKSimpleTextProvider(text: count(issueCount, unit: "Issue"))
            } else {
                textProvider = CLKSimpleTextProvider(text: count(prCount, unit: "Pull Request"))
            }
            let img = CLKComplicationTemplateGraphicCircularImage(
                imageProvider: CLKFullColorImageProvider(fullColorImage: UIImage(named: issues ? "ComplicationIssues" : "ComplicationPrs")!)
            )
            return CLKComplicationTemplateGraphicBezelCircularText(circularTemplate: img, textProvider: textProvider)
            
        case .graphicCircular:
            let gaugeProvider: CLKSimpleGaugeProvider
            let centerTextProvider: CLKSimpleTextProvider
            if commentCount > 0 {
                centerTextProvider = CLKSimpleTextProvider(text: String(commentCount))
                centerTextProvider.tintColor = .red
                gaugeProvider = CLKSimpleGaugeProvider(style: .fill, gaugeColor: .red, fillFraction: 1)
            } else if issues {
                centerTextProvider = CLKSimpleTextProvider(text: String(issueCount ?? 0))
                gaugeProvider = CLKSimpleGaugeProvider(style: .fill, gaugeColor: .white, fillFraction: 0)
            } else {
                centerTextProvider = CLKSimpleTextProvider(text: String(prCount ?? 0))
                gaugeProvider = CLKSimpleGaugeProvider(style: .fill, gaugeColor: .white, fillFraction: 0)
            }
            return CLKComplicationTemplateGraphicCircularClosedGaugeText(gaugeProvider: gaugeProvider, centerTextProvider: centerTextProvider)
            
        case .graphicRectangular:
            let headerTextProvider = CLKSimpleTextProvider(text: count(commentCount, unit: "Comment"))
            headerTextProvider.tintColor = commentCount > 0 ? .red : .white
            return CLKComplicationTemplateGraphicRectangularStandardBody(
                headerImageProvider: CLKFullColorImageProvider(fullColorImage: UIImage(named: "ComplicationPrs")!),
                headerTextProvider: headerTextProvider,
                body1TextProvider: CLKSimpleTextProvider(text: count(prCount, unit: "Pull Request")),
                body2TextProvider: CLKSimpleTextProvider(text: count(issueCount, unit: "Issue")))
            
        case .graphicExtraLarge:
            return CLKComplicationTemplateGraphicExtraLargeCircularStackText(
                line1TextProvider: CLKSimpleTextProvider(text: "\(issues ? (issueCount ?? 0) : (prCount ?? 0)) \(issues ? "Iss" : "PRs")"),
                line2TextProvider: CLKSimpleTextProvider(text: commentCount == 0 ? "- Com" : "\(commentCount) Com"))
            
        @unknown default:
            abort()
        }
	}
}
