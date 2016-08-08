
#if os(iOS)

import UIKit

let REFRESH_STARTED_NOTIFICATION = "RefreshStartedNotification"
let REFRESH_ENDED_NOTIFICATION = "RefreshEndedNotification"
let GLOBAL_SCREEN_SCALE = UIScreen.main.scale
let GLOBAL_TINT = UIColor(red: 52.0/255.0, green: 110.0/255.0, blue: 183.0/255.0, alpha: 1.0)
let DISABLED_FADE: CGFloat = 0.3

let stringDrawingOptions: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
typealias COLOR_CLASS = UIColor
typealias FONT_CLASS = UIFont
typealias IMAGE_CLASS = UIImage

#elseif os(OSX)

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

let stringDrawingOptions: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
typealias COLOR_CLASS = NSColor
typealias FONT_CLASS = NSFont
typealias IMAGE_CLASS = NSImage

#endif

////////////////////// Global variables
var appIsRefreshing = false
var preferencesDirty = false
var lastRepoCheck = Date.distantPast
let autoSnoozeDate = Date.distantFuture.addingTimeInterval(-1)

//////////////////////////

let itemDateFormatter = { () -> DateFormatter in
	let f = DateFormatter()
	f.dateStyle = .medium
	f.timeStyle = .short
	f.doesRelativeDateFormatting = true
	return f
	}()

//////////////////////// Logging: Ugly as hell but works and is fast

func DLog(_ message: String) {
    if Settings.logActivityToConsole {
        NSLog(message)
    }
}

func DLog(_ message: String, _ arg1: @autoclosure ()->CVarArg?) {
    if Settings.logActivityToConsole {
        NSLog(message, arg1() ?? "(nil)")
    }
}

func DLog(_ message: String, _ arg1: @autoclosure ()->CVarArg?, _ arg2: @autoclosure ()->CVarArg?) {
    if Settings.logActivityToConsole {
        NSLog(message, arg1() ?? "(nil)", arg2() ?? "(nil)")
    }
}

func DLog(_ message: String, _ arg1: @autoclosure ()->CVarArg?, _ arg2: @autoclosure ()->CVarArg?, _ arg3: @autoclosure ()->CVarArg?) {
    if Settings.logActivityToConsole {
        NSLog(message, arg1() ?? "(nil)", arg2() ?? "(nil)", arg3() ?? "(nil)")
    }
}

func DLog(_ message: String, _ arg1: @autoclosure ()->CVarArg?, _ arg2: @autoclosure ()->CVarArg?, _ arg3: @autoclosure ()->CVarArg?, _ arg4: @autoclosure ()->CVarArg?) {
	if Settings.logActivityToConsole {
		NSLog(message, arg1() ?? "(nil)", arg2() ?? "(nil)", arg3() ?? "(nil)", arg4() ?? "(nil)")
	}
}

func DLog(_ message: String, _ arg1: @autoclosure ()->CVarArg?, _ arg2: @autoclosure ()->CVarArg?, _ arg3: @autoclosure ()->CVarArg?, _ arg4: @autoclosure ()->CVarArg?, _ arg5: @autoclosure ()->CVarArg?) {
	if Settings.logActivityToConsole {
		NSLog(message, arg1() ?? "(nil)", arg2() ?? "(nil)", arg3() ?? "(nil)", arg4() ?? "(nil)", arg5() ?? "(nil)")
	}
}

let itemCountFormatter = { () -> NumberFormatter in
    let n = NumberFormatter()
    n.numberStyle = NumberFormatter.Style.decimal
    return n
}()

enum ItemCondition: Int {
	case open, closed, merged
}

enum StatusFilter: Int {
	case all, include, exclude
}

enum PostSyncAction: Int {
	case doNothing, delete, noteNew, noteUpdated
}

enum NotificationType: Int {
	case newComment, newPr, prMerged, prReopened, newMention, prClosed, newRepoSubscribed, newRepoAnnouncement, newPrAssigned, newStatus, newIssue, issueClosed, newIssueAssigned, issueReopened
}

enum SortingMethod: Int {
	case creationDate, recentActivity, title
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
		case .creationDate: return "createdAt"
		case .recentActivity: return "updatedAt"
		case .title: return "title"
		}
	}
}

enum HandlingPolicy: Int {
	case keepMine, keepMineAndParticipated, keepAll, keepNone
	static let labels = ["Keep Mine", "Keep Mine & Participated", "Keep All", "Don't Keep"]
	func name() -> String {
		return HandlingPolicy.labels[rawValue]
	}
}

enum AssignmentPolicy: Int {
	case moveToMine, moveToParticipated, doNothing
	static let labels = ["Move To Mine", "Move To Participated", "Do Nothing"]
	func name() -> String {
		return AssignmentPolicy.labels[rawValue]
	}
}

enum RepoDisplayPolicy: Int {
	case hide, mine, mineAndPaticipated, all
	static let labels = ["Hide", "Mine", "Participated", "All"]
	static let policies = [hide, mine, mineAndPaticipated, all]
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
	func name() -> String {
		return RepoHidingPolicy.labels[rawValue]
	}
	func color() -> COLOR_CLASS {
		return RepoHidingPolicy.colors[rawValue]
	}
}

func MAKECOLOR(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat) -> COLOR_CLASS {
	return COLOR_CLASS(red: red, green: green, blue: blue, alpha: alpha)
}

let LISTABLE_URI_KEY = "listableUriKey"
let COMMENT_ID_KEY = "commentIdKey"
let NOTIFICATION_URL_KEY = "urlKey"
let API_USAGE_UPDATE = "RateUpdateNotification"
let kSyncProgressUpdate = "kSyncProgressUpdate"

let LOW_API_WARNING: Double = 0.20
let BACKOFF_STEP: TimeInterval = 120.0

func currentAppVersion() -> String {
	return S(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
}

#if os(iOS)

	import UIKit
	import CoreData

	func colorToHex(c: COLOR_CLASS) -> String {
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		c.getRed(&r, green: &g, blue: &b, alpha: &a)
		r *= 255.0
		g *= 255.0
		b *= 255.0
		return NSString(format: "%02X%02X%02X", Int(r), Int(g), Int(b)) as String
	}

#elseif os(OSX)

	func hasModifier(_ event: NSEvent, _ modifier: NSEventModifierFlags) -> Bool {
		return (event.modifierFlags.intersection(modifier)) == modifier
	}

#endif

func versionString() -> String {
	let buildNumber = S(Bundle.main.infoDictionary?["CFBundleVersion"] as? String)
	return "Version \(currentAppVersion()) (\(buildNumber))"
}

func existingObjectWithID(_ id: NSManagedObjectID) -> NSManagedObject? {
	return try? mainObjectContext.existingObject(with: id)
}

func isDarkColor(_ color: COLOR_CLASS) -> Bool {
	var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
	color.getRed(&r, green: &g, blue: &b, alpha: nil)
	let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
	return (lum < 0.5)
}

func parseFromHex(_ s: String) -> UInt32 {
	let safe = s.trim().trimmingCharacters(in: CharacterSet.symbols)
	let s = Scanner(string: safe)
	var result:UInt32 = 0
	s.scanHexInt32(&result)
	return result
}

func colorFromUInt32(_ c: UInt32) -> COLOR_CLASS {
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
	func stringByAppendingPathComponent(_ path: String) -> String {
		return (self as NSString).appendingPathComponent(path)
	}
	func stringByReplacingCharactersInRange(_ range: NSRange, withString string: String) -> String {
		return (self as NSString).replacingCharacters(in: range, with: string)
	}
	func trim() -> String {
		return self.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
	}
	var md5hash: String {
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

