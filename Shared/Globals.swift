
#if os(iOS)

import UIKit

let REFRESH_STARTED_NOTIFICATION = "RefreshStartedNotification"
let REFRESH_ENDED_NOTIFICATION = "RefreshEndedNotification"
let GLOBAL_SCREEN_SCALE = UIScreen.mainScreen().scale
let GLOBAL_TINT = UIColor(red: 52.0/255.0, green: 110.0/255.0, blue: 183.0/255.0, alpha: 1.0)
let DISABLED_FADE: CGFloat = 0.3

let stringDrawingOptions: NSStringDrawingOptions = [.UsesLineFragmentOrigin, .UsesFontLeading]
typealias COLOR_CLASS = UIColor
typealias FONT_CLASS = UIFont
typealias IMAGE_CLASS = UIImage

#elseif os(OSX)

let STATUSITEM_PADDING: CGFloat = 1.0
let TOP_HEADER_HEIGHT: CGFloat = 28.0
let AVATAR_SIZE: CGFloat = 26.0
let LEFTPADDING: CGFloat = 44.0
let TITLE_HEIGHT: CGFloat = 42.0
let BASE_BADGE_SIZE: CGFloat = 20.0
let SMALL_BADGE_SIZE: CGFloat = 14.0
let MENU_WIDTH: CGFloat = 500.0
let AVATAR_PADDING: CGFloat = 8.0
let REMOVE_BUTTON_WIDTH: CGFloat = 80.0
let DISABLED_FADE: CGFloat = 0.4

let stringDrawingOptions: NSStringDrawingOptions = [.UsesLineFragmentOrigin, .UsesFontLeading]
typealias COLOR_CLASS = NSColor
typealias FONT_CLASS = NSFont
typealias IMAGE_CLASS = NSImage

#endif

////////////////////// Global variables
var appIsRefreshing = false
var preferencesDirty = false
var lastRepoCheck = never()

//////////////////////////

let itemDateFormatter = { () -> NSDateFormatter in
	let f = NSDateFormatter()
	f.dateStyle = .MediumStyle
	f.timeStyle = .ShortStyle
	f.doesRelativeDateFormatting = true
	return f
	}()

//////////////////////// Logging: Ugly as hell but works and is fast

func DLog(message: String) {
    if Settings.logActivityToConsole {
        NSLog(message)
    }
}

func DLog(message: String, @autoclosure _ arg1: ()->CVarArgType?) {
    if Settings.logActivityToConsole {
        NSLog(message, arg1() ?? "(nil)")
    }
}

func DLog(message: String, @autoclosure _ arg1: ()->CVarArgType?, @autoclosure _ arg2: ()->CVarArgType?) {
    if Settings.logActivityToConsole {
        NSLog(message, arg1() ?? "(nil)", arg2() ?? "(nil)")
    }
}

func DLog(message: String, @autoclosure _ arg1: ()->CVarArgType?, @autoclosure _ arg2: ()->CVarArgType?, @autoclosure _ arg3: ()->CVarArgType?) {
    if Settings.logActivityToConsole {
        NSLog(message, arg1() ?? "(nil)", arg2() ?? "(nil)", arg3() ?? "(nil)")
    }
}

func DLog(message: String, @autoclosure _ arg1: ()->CVarArgType?, @autoclosure _ arg2: ()->CVarArgType?, @autoclosure _ arg3: ()->CVarArgType?, @autoclosure _ arg4: ()->CVarArgType?) {
	if Settings.logActivityToConsole {
		NSLog(message, arg1() ?? "(nil)", arg2() ?? "(nil)", arg3() ?? "(nil)", arg4() ?? "(nil)")
	}
}

func DLog(message: String, @autoclosure _ arg1: ()->CVarArgType?, @autoclosure _ arg2: ()->CVarArgType?, @autoclosure _ arg3: ()->CVarArgType?, @autoclosure _ arg4: ()->CVarArgType?, @autoclosure _ arg5: ()->CVarArgType?) {
	if Settings.logActivityToConsole {
		NSLog(message, arg1() ?? "(nil)", arg2() ?? "(nil)", arg3() ?? "(nil)", arg4() ?? "(nil)", arg5() ?? "(nil)")
	}
}

let itemCountFormatter = { () -> NSNumberFormatter in
    let n = NSNumberFormatter()
    n.numberStyle = NSNumberFormatterStyle.DecimalStyle
    return n
}()

enum ItemCondition: Int {
	case Open, Closed, Merged
}

enum StatusFilter: Int {
	case All, Include, Exclude
}

enum PostSyncAction: Int {
	case DoNothing, Delete, NoteNew, NoteUpdated
}

enum NotificationType: Int {
	case NewComment, NewPr, PrMerged, PrReopened, NewMention, PrClosed, NewRepoSubscribed, NewRepoAnnouncement, NewPrAssigned, NewStatus, NewIssue, IssueClosed, NewIssueAssigned, IssueReopened
}

enum SortingMethod: Int {
	case CreationDate, RecentActivity, Title
	static let reverseTitles = ["Youngest first", "Most recently active", "Reverse alphabetically"]
	static let normalTitles = ["Oldest first", "Inactive for longest", "Alphabetically"]

	func normalTitle() -> String {
		return SortingMethod.normalTitles[rawValue]
	}

	func reverseTitle() -> String {
		return SortingMethod.reverseTitles[rawValue]
	}

	func field() -> String? {
		switch self {
		case .CreationDate: return "createdAt"
		case .RecentActivity: return "updatedAt"
		case .Title: return "title"
		}
	}
}

enum HandlingPolicy: Int {
	case KeepMine, KeepMineAndParticipated, KeepAll, KeepNone
	static let labels = ["Keep Mine", "Keep Mine & Participated", "Keep All", "Don't Keep"]
	func name() -> String {
		return HandlingPolicy.labels[rawValue]
	}
}

enum AssignmentPolicy: Int {
	case MoveToMine, MoveToParticipated, DoNothing
	static let labels = ["Move To Mine", "Move To Participated", "Do Nothing"]
	func name() -> String {
		return AssignmentPolicy.labels[rawValue]
	}
}

enum RepoDisplayPolicy: Int {
	case Hide, Mine, MineAndPaticipated, All
	static let labels = ["Hide", "Mine", "Participated", "All"]
	static let policies = [Hide, Mine, MineAndPaticipated, All]
	static let colors = [	COLOR_CLASS(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0),
							COLOR_CLASS(red: 0.7, green: 0.0, blue: 0.0, alpha: 1.0),
							COLOR_CLASS(red: 0.8, green: 0.4, blue: 0.0, alpha: 1.0),
							COLOR_CLASS(red: 0.0, green: 0.5, blue: 0.0, alpha: 1.0)]
	func name() -> String {
		return RepoDisplayPolicy.labels[rawValue]
	}
	func color() -> COLOR_CLASS {
		return RepoDisplayPolicy.colors[rawValue]
	}
}

enum RepoHidingPolicy: Int {
	case NoHiding, HideMyAuthoredPrs, HideMyAuthoredIssues, HideAllMyAuthoredItems, HideOthersPrs, HideOthersIssues, HideAllOthersItems
	static let labels = ["No Filter", "Hide My PRs", "Hide My Issues", "Hide All Mine", "Hide Others PRs", "Hide Others Issues", "Hide All Others"]
	static let policies = [NoHiding, HideMyAuthoredPrs, HideMyAuthoredIssues, HideAllMyAuthoredItems, HideOthersPrs, HideOthersIssues, HideAllOthersItems]
	static let colors = [	COLOR_CLASS.lightGrayColor(),
							COLOR_CLASS(red: 0.1, green: 0.1, blue: 0.5, alpha: 1.0),
							COLOR_CLASS(red: 0.1, green: 0.1, blue: 0.5, alpha: 1.0),
							COLOR_CLASS(red: 0.1, green: 0.1, blue: 0.5, alpha: 1.0),
							COLOR_CLASS(red: 0.5, green: 0.1, blue: 0.1, alpha: 1.0),
							COLOR_CLASS(red: 0.5, green: 0.1, blue: 0.1, alpha: 1.0),
							COLOR_CLASS(red: 0.5, green: 0.1, blue: 0.1, alpha: 1.0)]
	func name() -> String {
		return RepoHidingPolicy.labels[rawValue]
	}
	func color() -> COLOR_CLASS {
		return RepoHidingPolicy.colors[rawValue]
	}
}

func MAKECOLOR(red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat) -> COLOR_CLASS {
	return COLOR_CLASS(red: red, green: green, blue: blue, alpha: alpha)
}

let PULL_REQUEST_ID_KEY = "pullRequestIdKey"
let ISSUE_ID_KEY = "issueIdKey"
let STATUS_ID_KEY = "statusIdKey"
let COMMENT_ID_KEY = "commentIdKey"
let NOTIFICATION_URL_KEY = "urlKey"
let API_USAGE_UPDATE = "RateUpdateNotification"

let LOW_API_WARNING: Double = 0.20
let BACKOFF_STEP: NSTimeInterval = 120.0

func currentAppVersion() -> String {
	return S(NSBundle.mainBundle().infoDictionary?["CFBundleShortVersionString"] as? String)
}

#if os(iOS)

	import UIKit
	import CoreData

	enum MasterViewMode: Int {
		case PullRequests, Issues
		static let namesPlural = ["Pull Requests", "Issues"]
		func namePlural() -> String {
			return MasterViewMode.namesPlural[rawValue]
		}
		static let namesSingular = ["Pull Request", "Issue"]
		func nameSingular() -> String {
			return MasterViewMode.namesSingular[rawValue]
		}
	}

	func colorToHex(c: COLOR_CLASS) -> String {
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		c.getRed(&r, green: &g, blue: &b, alpha: &a)
		r *= 255.0
		g *= 255.0
		b *= 255.0
		return NSString(format: "%02X%02X%02X", Int(r), Int(g), Int(b)) as String
	}

#elseif os(OSX)

	func hasModifier(event: NSEvent, _ modifier: NSEventModifierFlags) -> Bool {
		return (event.modifierFlags.intersect(modifier)) == modifier
	}

#endif

func versionString() -> String {
	let buildNumber = S(NSBundle.mainBundle().infoDictionary?["CFBundleVersion"] as? String)
	return "Version \(currentAppVersion()) (\(buildNumber))"
}

func existingObjectWithID(id: NSManagedObjectID) -> NSManagedObject? {
	return try? mainObjectContext.existingObjectWithID(id)
}

func isDarkColor(color: COLOR_CLASS) -> Bool {
	var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
	color.getRed(&r, green: &g, blue: &b, alpha: nil)
	let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
	return (lum < 0.5)
}

func parseFromHex(s: String) -> UInt32 {
	let safe = s.trim().stringByTrimmingCharactersInSet(NSCharacterSet.symbolCharacterSet())
	let s = NSScanner(string: safe)
	var result:UInt32 = 0
	s.scanHexInt(&result)
	return result
}

func colorFromUInt32(c: UInt32) -> COLOR_CLASS {
	let red: UInt32 = (c & 0xFF0000)>>16
	let green: UInt32 = (c & 0x00FF00)>>8
	let blue: UInt32 = c & 0x0000FF
	let r = CGFloat(red)/255.0
	let g = CGFloat(green)/255.0
	let b = CGFloat(blue)/255.0
	return COLOR_CLASS(red: r, green: g, blue: b, alpha: 1.0)
}

//////////////////////// From tieferbegabt's post on https://forums.developer.apple.com/message/37935, with thanks!

extension String {
	func stringByAppendingPathComponent(path: String) -> String {
		return (self as NSString).stringByAppendingPathComponent(path)
	}
	func stringByReplacingCharactersInRange(range: NSRange, withString string: String) -> String {
		return (self as NSString).stringByReplacingCharactersInRange(range, withString: string)
	}
	func trim() -> String {
		return self.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
	}
	var md5hash: String {
		let digestLen = Int(CC_MD5_DIGEST_LENGTH)
		let result = UnsafeMutablePointer<CUnsignedChar>.alloc(digestLen)

		CC_MD5(
			self.cStringUsingEncoding(NSUTF8StringEncoding)!,
			CC_LONG(self.lengthOfBytesUsingEncoding(NSUTF8StringEncoding)),
			result)

		let hash = NSMutableString()
		for i in 0..<digestLen {
			hash.appendFormat("%02X", result[i])
		}

		result.destroy()

		return String(hash)
	}
}

