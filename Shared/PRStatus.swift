import Foundation

let darkStatusRed = MAKECOLOR(0.8, 0.5, 0.5, 1.0)
let darkStatusYellow = MAKECOLOR(0.9, 0.8, 0.3, 1.0)
let darkStatusGreen = MAKECOLOR(0.6, 0.8, 0.6, 1.0)
let lightStatusRed = MAKECOLOR(0.5, 0.2, 0.2, 1.0)
let lightStatusYellow = MAKECOLOR(0.6, 0.5, 0.0, 1.0)
let lightStatusGreen = MAKECOLOR(0.3, 0.5, 0.3, 1.0)

let dateFormatter = { () -> NSDateFormatter in
	let dateFormatter = NSDateFormatter()
	dateFormatter.dateStyle = NSDateFormatterStyle.ShortStyle
	dateFormatter.timeStyle = NSDateFormatterStyle.ShortStyle
	return dateFormatter
}()

@objc(PRStatus)
class PRStatus: DataItem {

    @NSManaged var descriptionText: String?
    @NSManaged var state: String?
    @NSManaged var targetUrl: String?
    @NSManaged var url: String?
    @NSManaged var userId: NSNumber?
    @NSManaged var userName: String?

	@NSManaged var pullRequest: PullRequest

	class func statusWithInfo(info: NSDictionary, fromServer: ApiServer) -> PRStatus {
		let s = DataItem.itemWithInfo(info, type: "PRStatus", fromServer: fromServer) as! PRStatus
		if s.postSyncAction?.integerValue != PostSyncAction.DoNothing.rawValue {
			s.url = info.ofk("url") as? String
			s.state = info.ofk("state") as? String
			s.targetUrl = info.ofk("target_url") as? String

            if let ds = info.ofk("description") as? String {
                s.descriptionText = ds.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
            }

			if let userInfo = info.ofk("creator") as? NSDictionary {
				s.userName = userInfo.ofk("login") as? String
				s.userId = userInfo.ofk("id") as? NSNumber
			}
		}
		return s
	}

	func colorForDarkDisplay() -> COLOR_CLASS {
		switch state! {
		case "pending":
			return darkStatusYellow
		case "success":
			return darkStatusGreen
		default:
			return darkStatusRed
		}
	}

	func colorForDisplay() -> COLOR_CLASS {
		switch state! {
		case "pending":
			return lightStatusYellow
		case "success":
			return lightStatusGreen
		default:
			return lightStatusRed
		}
	}

	func displayText() -> String {
		if let desc = descriptionText {
			return NSString(format: "%@ %@", dateFormatter.stringFromDate(createdAt!), desc) as String
		} else {
			return "(No description)"
		}
	}

}
