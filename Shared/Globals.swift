
///////////// Logging, with thanks to Transition.io: http://transition.io/logging-in-swift-without-overhead-in-production/

typealias LazyVarArgClosure = @autoclosure () -> CVarArgType?

func DLog(messageFormat:@autoclosure () -> String, args:LazyVarArgClosure...) {
	var shouldLog: Bool
	#if DEBUG
		shouldLog = true
	#else
		shouldLog = Settings.logActivityToConsole
	#endif
	if shouldLog {
		let realArgs:[CVarArgType] = args.map { (lazyArg:LazyVarArgClosure) in
			if let l = lazyArg() { return l } else { return "(nil)" }
		}

		func curriedStringWithFormat(valist:CVaListPointer) -> String {
			return NSString(format:messageFormat(), arguments:valist)
		}

		var s = withVaList(realArgs, curriedStringWithFormat)
		NSLog("%@", s)
	}
}

#if os(iOS)
	typealias COLOR_CLASS = UIColor
	typealias FONT_CLASS = UIFont
	typealias IMAGE_CLASS = UIImage
	let stringDrawingOptions = NSStringDrawingOptions.UsesLineFragmentOrigin
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

	typealias COLOR_CLASS = NSColor
	typealias FONT_CLASS = NSFont
	typealias IMAGE_CLASS = NSImage
	let stringDrawingOptions = NSStringDrawingOptions.UsesLineFragmentOrigin | NSStringDrawingOptions.UsesFontLeading
#endif

func MAKECOLOR(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> COLOR_CLASS {
	return COLOR_CLASS(red: red, green: green, blue: blue, alpha: alpha)
}

let PULL_REQUEST_ID_KEY = "pullRequestIdKey"
let COMMENT_ID_KEY = "commentIdKey"
let NOTIFICATION_URL_KEY = "urlKey"
let API_USAGE_UPDATE = "RateUpdateNotification"
let DARK_MODE_CHANGED = "DarkModeChangedNotificationKey"
let PR_ITEM_FOCUSED_STATE_KEY = "PrItemFocusedStateKey"
let UPDATE_VIBRANCY_NOTIFICATION = "UpdateVibrancyNotfication"

let LOW_API_WARNING: Double = 0.20
let NETWORK_TIMEOUT: NSTimeInterval = 120.0
let BACKOFF_STEP: NSTimeInterval = 120.0

let kPullRequestSectionNames = ["", "Mine", "Participated", "Recently Merged", "Recently Closed", "All Pull Requests"]
let currentAppVersion = NSBundle.mainBundle().infoDictionary!["CFBundleShortVersionString"] as String

enum PullRequestCondition: Int {
	case Open, Closed, Merged
}

enum PullRequestSection: Int {
	case None, Mine, Participated, Merged, Closed, All
}

enum StatusFilter: Int {
	case All, Include, Exclude
}

enum PostSyncAction: Int {
	case DoNothing, Delete, NoteNew, NoteUpdated
}

enum PRNotificationType: Int {
	case NewComment, NewPr, PrMerged, PrReopened, NewMention, PrClosed, NewRepoSubscribed, NewRepoAnnouncement, NewPrAssigned
}

enum PRSortingMethod: Int {
	case CreationDate, RecentActivity, Title, Repository
}

enum PRHandlingPolicy: Int {
	case KeepMine, KeepAll, KeepNone
}

