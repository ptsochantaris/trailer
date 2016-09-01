
#if os(iOS)

import UIKit

weak var app: iOS_AppDelegate!

let GLOBAL_SCREEN_SCALE = UIScreen.main.scale
let GLOBAL_TINT = UIColor(red: 52.0/255.0, green: 110.0/255.0, blue: 183.0/255.0, alpha: 1.0)
let DISABLED_FADE: CGFloat = 0.3

typealias COLOR_CLASS = UIColor
typealias FONT_CLASS = UIFont
typealias IMAGE_CLASS = UIImage

#elseif os(OSX)

weak var app: OSX_AppDelegate!

let AVATAR_SIZE: CGFloat = 26
let AVATAR_PADDING: CGFloat = 8
let LEFTPADDING: CGFloat = 44
let MENU_WIDTH: CGFloat = 500
let REMOVE_BUTTON_WIDTH: CGFloat = 80
let DISABLED_FADE: CGFloat = 0.4

typealias COLOR_CLASS = NSColor
typealias FONT_CLASS = NSFont
typealias IMAGE_CLASS = NSImage

#endif

////////////////////// Global variables

var appIsRefreshing = false
var preferencesDirty = false
var lastRepoCheck = Date.distantPast
let autoSnoozeDate = Date.distantFuture.addingTimeInterval(-1)
let stringDrawingOptions: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
let LISTABLE_URI_KEY = "listableUriKey"
let COMMENT_ID_KEY = "commentIdKey"
let NOTIFICATION_URL_KEY = "urlKey"

////////////////////////// Utilities

#if os(iOS)
	import CoreData

func showMessage(_ title: String, _ message: String?) {
	var viewController = app.window?.rootViewController
	while viewController?.presentedViewController != nil {
		viewController = viewController?.presentedViewController
	}

	let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
	a.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
	viewController?.present(a, animated: true, completion: nil)
}
#endif

func existingObject(with id: NSManagedObjectID) -> NSManagedObject? {
	return try? DataManager.main.existingObject(with: id)
}

let itemDateFormatter = { () -> DateFormatter in
	let f = DateFormatter()
	f.dateStyle = .medium
	f.timeStyle = .short
	f.doesRelativeDateFormatting = true
	return f
}()

func DLog(_ message: String, _ arg1: @autoclosure ()->Any? = nil, _ arg2: @autoclosure ()->Any? = nil, _ arg3: @autoclosure ()->Any? = nil, _ arg4: @autoclosure ()->Any? = nil, _ arg5: @autoclosure ()->Any? = nil) {
	if Settings.logActivityToConsole {
		NSLog(message,
		      String(describing: arg1() ?? "(nil)"),
		      String(describing: arg2() ?? "(nil)"),
		      String(describing: arg3() ?? "(nil)"),
		      String(describing: arg4() ?? "(nil)"),
		      String(describing: arg5() ?? "(nil)"))
	}
}

let itemCountFormatter = { () -> NumberFormatter in
    let n = NumberFormatter()
    n.numberStyle = .decimal
    return n
}()

// Single-purpose derivation from the excellent SAMAdditions:
// https://github.com/soffes/SAMCategories/blob/master/SAMCategories/NSDate%2BSAMAdditions.m
private let dateParserHolder = "                   +0000".cString(using: String.Encoding.ascii)!
func parseGH8601(_ iso8601: String?) -> Date? {

	guard let i = iso8601, i.characters.count >= 19 else { return nil }

	var fullString = dateParserHolder
	memcpy(&fullString, i, 19)

	var tt = tm()
	strptime(fullString, "%FT%T%z", &tt)

	let t = mktime(&tt)
	return Date(timeIntervalSince1970: TimeInterval(t))
}

func bootUp() {
	Settings.checkMigration()
	DataManager.checkMigration()
	API.setup()
}

//////////////////////// Enums

enum ItemCondition: Int64 {
	case open, closed, merged
}

enum StatusFilter: Int {
	case all, include, exclude
}

enum PostSyncAction: Int64 {
	case doNothing, delete, noteNew, noteUpdated
}

enum NotificationType: Int {
	case newComment, newPr, prMerged, prReopened, newMention, prClosed, newRepoSubscribed, newRepoAnnouncement, newPrAssigned, newStatus, newIssue, issueClosed, newIssueAssigned, issueReopened
}

enum SortingMethod: Int {
	case creationDate, recentActivity, title
	static let reverseTitles = ["Youngest first", "Most recently active", "Reverse alphabetically"]
	static let normalTitles = ["Oldest first", "Inactive for longest", "Alphabetically"]

	init?(_ rawValue: Int) {
		self.init(rawValue: rawValue)
	}

	var normalTitle: String {
		return SortingMethod.normalTitles[rawValue]
	}

	var reverseTitle: String {
		return SortingMethod.reverseTitles[rawValue]
	}

	var field: String? {
		switch self {
		case .creationDate: return "createdAt"
		case .recentActivity: return "updatedAt"
		case .title: return "title"
		}
	}
}

enum HandlingPolicy: Int {
	case keepMine, keepMineAndParticipated, keepAll, keepNone
	static let labels = ["Keep Mine", "Keep Mine & Participated", "Keep All", "Don't Keep"]
	var name: String {
		return HandlingPolicy.labels[rawValue]
	}
	init?(_ rawValue: Int) {
		self.init(rawValue: rawValue)
	}
}

enum AssignmentPolicy: Int {
	case moveToMine, moveToParticipated, doNothing
	static let labels = ["Move To Mine", "Move To Participated", "Do Nothing"]
	var name: String {
		return AssignmentPolicy.labels[rawValue]
	}
	init?(_ rawValue: Int) {
		self.init(rawValue: rawValue)
	}
}

enum RepoDisplayPolicy: Int64 {
	case hide, mine, mineAndPaticipated, all
	static let labels = ["Hide", "Mine", "Participated", "All"]
	static let policies = [hide, mine, mineAndPaticipated, all]
	static let colors = [	COLOR_CLASS(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0),
							COLOR_CLASS(red: 0.7, green: 0.0, blue: 0.0, alpha: 1.0),
							COLOR_CLASS(red: 0.8, green: 0.4, blue: 0.0, alpha: 1.0),
							COLOR_CLASS(red: 0.0, green: 0.5, blue: 0.0, alpha: 1.0)]
	var name: String {
		return RepoDisplayPolicy.labels[Int(rawValue)]
	}
	var color: COLOR_CLASS {
		return RepoDisplayPolicy.colors[Int(rawValue)]
	}
	var intValue: Int { return Int(rawValue) }

	init?(_ rawValue: Int64) {
		self.init(rawValue: rawValue)
	}
	init?(_ rawValue: Int) {
		self.init(rawValue: Int64(rawValue))
	}
}

enum RepoHidingPolicy: Int64 {
	case noHiding, hideMyAuthoredPrs, hideMyAuthoredIssues, hideAllMyAuthoredItems, hideOthersPrs, hideOthersIssues, hideAllOthersItems
	static let labels = ["No Filter", "Hide My PRs", "Hide My Issues", "Hide All Mine", "Hide Others PRs", "Hide Others Issues", "Hide All Others"]
	static let policies = [noHiding, hideMyAuthoredPrs, hideMyAuthoredIssues, hideAllMyAuthoredItems, hideOthersPrs, hideOthersIssues, hideAllOthersItems]
	static let colors = [	COLOR_CLASS.lightGray,
							COLOR_CLASS(red: 0.1, green: 0.1, blue: 0.5, alpha: 1.0),
							COLOR_CLASS(red: 0.1, green: 0.1, blue: 0.5, alpha: 1.0),
							COLOR_CLASS(red: 0.1, green: 0.1, blue: 0.5, alpha: 1.0),
							COLOR_CLASS(red: 0.5, green: 0.1, blue: 0.1, alpha: 1.0),
							COLOR_CLASS(red: 0.5, green: 0.1, blue: 0.1, alpha: 1.0),
							COLOR_CLASS(red: 0.5, green: 0.1, blue: 0.1, alpha: 1.0)]
	var name: String {
		return RepoHidingPolicy.labels[Int(rawValue)]
	}
	var color: COLOR_CLASS {
		return RepoHidingPolicy.colors[Int(rawValue)]
	}
	init?(_ rawValue: Int64) {
		self.init(rawValue: rawValue)
	}
	init?(_ rawValue: Int) {
		self.init(rawValue: Int64(rawValue))
	}
}

var currentAppVersion: String {
	return S(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
}

var versionString: String {
	let buildNumber = S(Bundle.main.infoDictionary?["CFBundleVersion"] as? String)
	return "Version \(currentAppVersion) (\(buildNumber))"
}

//////////////////////// Originally from tieferbegabt's post on https://forums.developer.apple.com/message/37935, with thanks!

extension String {
	func appending(pathComponent: String) -> String {
		let endSlash = hasSuffix("/")
		let firstSlash = pathComponent.hasPrefix("/")
		if endSlash && firstSlash {
			let firstChar = pathComponent.index(pathComponent.startIndex, offsetBy: 1)
			return appending(pathComponent.substring(from: firstChar))
		} else if (!endSlash && !firstSlash) {
			return appending("/\(pathComponent)")
		} else {
			return appending(pathComponent)
		}
	}
	func replacingCharacters(in range: NSRange, with string: String) -> String {
		let l = index(startIndex, offsetBy: range.location)
		let u = index(l, offsetBy: range.length)
		let r = Range(uncheckedBounds: (lower: l, upper: u))
		return replacingCharacters(in: r, with: string)
	}
	var trim: String {
		return trimmingCharacters(in: .whitespacesAndNewlines)
	}
	var md5hashed: String {
		let digestLen = Int(CC_MD5_DIGEST_LENGTH)
		let result = UnsafeMutablePointer<CUnsignedChar>.allocate(capacity: digestLen)

		CC_MD5(
			self.cString(using: String.Encoding.utf8)!,
			CC_LONG(self.lengthOfBytes(using: String.Encoding.utf8)),
			result)

		var hash = String()
		for i in 0..<digestLen {
			let digit = String(format: "%02X", result[i])
			hash.append(digit)
		}

		result.deinitialize()
		return hash
	}
}

////////////////////// Notifications

let RefreshStartedNotification = Notification.Name("RefreshStartedNotification")
let RefreshEndedNotification = Notification.Name("RefreshEndedNotification")
let SyncProgressUpdateNotification = Notification.Name("SyncProgressUpdateNotification")
let ApiUsageUpdateNotification = Notification.Name("ApiUsageUpdateNotification")
let AppleInterfaceThemeChangedNotification = Notification.Name("AppleInterfaceThemeChangedNotification")
let SettingsExportedNotification = Notification.Name("SettingsExportedNotification")

