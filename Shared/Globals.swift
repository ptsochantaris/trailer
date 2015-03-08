
///////////// Logging, with thanks to Transition.io: http://transition.io/logging-in-swift-without-overhead-in-production/

typealias LazyVarArgClosure = @autoclosure () -> CVarArgType?

func DLog(messageFormat: String, args: LazyVarArgClosure...) {
	#if DEBUG
		let shouldLog = true
	#else
		let shouldLog = Settings.logActivityToConsole
	#endif
	if shouldLog {
		withVaList(
			args.map { (lazyArg: LazyVarArgClosure) in
				return lazyArg() ?? "(nil)"
			}, {
				NSLogv(messageFormat, $0)
			}
		)
	}
}

#if os(iOS)

	import UIKit

	typealias COLOR_CLASS = UIColor
	typealias FONT_CLASS = UIFont
	typealias IMAGE_CLASS = UIImage
	let stringDrawingOptions = NSStringDrawingOptions.UsesLineFragmentOrigin

	let REFRESH_STARTED_NOTIFICATION = "RefreshStartedNotification"
	let REFRESH_ENDED_NOTIFICATION = "RefreshEndedNotification"
	let RECEIVED_NOTIFICATION_KEY = "ReceivedNotificationKey"
	let GLOBAL_SCREEN_SCALE = UIScreen.mainScreen().scale

#elseif os(OSX)

	let STATUSITEM_PADDING: CGFloat = 1.0
	let TOP_HEADER_HEIGHT: CGFloat = 28.0
	let AVATAR_SIZE: CGFloat = 26.0
	let LEFTPADDING: CGFloat = 44.0
	let TITLE_HEIGHT: CGFloat = 42.0
	let BASE_BADGE_SIZE: CGFloat = 21.0
	let SMALL_BADGE_SIZE: CGFloat = 14.0
	let MENU_WIDTH: CGFloat = 500.0
	let AVATAR_PADDING: CGFloat = 8.0
	let REMOVE_BUTTON_WIDTH: CGFloat = 80.0

	let DARK_MODE_CHANGED = "DarkModeChangedNotificationKey"
	let PR_ITEM_FOCUSED_STATE_KEY = "PrItemFocusedStateKey"
	let UPDATE_VIBRANCY_NOTIFICATION = "UpdateVibrancyNotfication"

	typealias COLOR_CLASS = NSColor
	typealias FONT_CLASS = NSFont
	typealias IMAGE_CLASS = NSImage
	let stringDrawingOptions = NSStringDrawingOptions.UsesLineFragmentOrigin | NSStringDrawingOptions.UsesFontLeading

#endif

let itemCountFormatter = { () -> NSNumberFormatter in
    let n = NSNumberFormatter()
    n.numberStyle = NSNumberFormatterStyle.DecimalStyle
    return n
}()

let syncDateFormatter = { () -> NSDateFormatter in
    let d = NSDateFormatter()
    d.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'"
    d.timeZone = NSTimeZone(abbreviation: "UTC")
    d.locale = NSLocale(localeIdentifier: "en_US")
    return d
}()

func MAKECOLOR(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> COLOR_CLASS {
	return COLOR_CLASS(red: red, green: green, blue: blue, alpha: alpha)
}

let PULL_REQUEST_ID_KEY = "pullRequestIdKey"
let STATUS_ID_KEY = "statusIdKey"
let COMMENT_ID_KEY = "commentIdKey"
let NOTIFICATION_URL_KEY = "urlKey"
let API_USAGE_UPDATE = "RateUpdateNotification"

let LOW_API_WARNING: Double = 0.20
let NETWORK_TIMEOUT: NSTimeInterval = 120.0
let BACKOFF_STEP: NSTimeInterval = 120.0

let currentAppVersion = NSBundle.mainBundle().infoDictionary!["CFBundleShortVersionString"] as String

enum PullRequestCondition: Int {
	case Open, Closed, Merged
}

enum PullRequestSection: Int {
	case None, Mine, Participated, Merged, Closed, All
	static let allTitles = ["", "Mine", "Participated", "Recently Merged", "Recently Closed", "All Pull Requests"]
	func name() -> String {
		return PullRequestSection.allTitles[rawValue]
	}
}

enum StatusFilter: Int {
	case All, Include, Exclude
}

enum PostSyncAction: Int {
	case DoNothing, Delete, NoteNew, NoteUpdated
}

enum PRNotificationType: Int {
	case NewComment, NewPr, PrMerged, PrReopened, NewMention, PrClosed, NewRepoSubscribed, NewRepoAnnouncement, NewPrAssigned, NewStatus
}

enum PRSortingMethod: Int {
	case CreationDate, RecentActivity, Title, Repository
}

enum PRHandlingPolicy: Int {
	case KeepMine, KeepAll, KeepNone
}

