
////////////////////// Global variables

#if os(iOS)

import UIKit
import CoreData

weak var app: iOSAppDelegate!

let GLOBAL_SCREEN_SCALE = UIScreen.main.scale
let DISABLED_FADE: CGFloat = 0.3

typealias FONT_CLASS = UIFont
typealias IMAGE_CLASS = UIImage

let stringDrawingOptions: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

func makeKeyCommand(input: String, modifierFlags: UIKeyModifierFlags, action: Selector, discoverabilityTitle: String) -> UIKeyCommand {
    return UIKeyCommand(title: discoverabilityTitle, image: nil, action: action, input: input, modifierFlags: modifierFlags, propertyList: nil, alternates: [], discoverabilityTitle: nil, attributes: [], state: .off)
}

let compactTraits = UITraitCollection(horizontalSizeClass: .compact)

#elseif os(OSX)

weak var app: MacAppDelegate!

let AVATAR_SIZE: CGFloat = 26
let AVATAR_PADDING: CGFloat = 8
let LEFTPADDING: CGFloat = 44
let MENU_WIDTH: CGFloat = 500
let REMOVE_BUTTON_WIDTH: CGFloat = 80
let DISABLED_FADE: CGFloat = 0.4

typealias FONT_CLASS = NSFont
typealias IMAGE_CLASS = NSImage

let stringDrawingOptions: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

#endif

var preferencesDirty = false
var lastRepoCheck = Date.distantPast
let autoSnoozeSentinelDate = Date.distantFuture.addingTimeInterval(-1)
let LISTABLE_URI_KEY = "listableUriKey"
let COMMENT_ID_KEY = "commentIdKey"
let NOTIFICATION_URL_KEY = "urlKey"

////////////////////////// Utilities

#if os(iOS)

	func showMessage(_ title: String, _ message: String?) {
		var viewController = app.window?.rootViewController
		while viewController?.presentedViewController != nil {
			viewController = viewController?.presentedViewController
		}

		let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
		a.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
		viewController?.present(a, animated: true)
	}

#endif

let emptyAttributedString = NSAttributedString()

func existingObject(with id: NSManagedObjectID) -> NSManagedObject? {
	return try? DataManager.main.existingObject(with: id)
}

let itemDateFormatter: DateFormatter = {
	let f = DateFormatter()
	f.dateStyle = .medium
	f.timeStyle = .short
	f.doesRelativeDateFormatting = true
	return f
}()

func DLog(_ message: String, _ arg1: @autoclosure ()->Any? = nil, _ arg2: @autoclosure ()->Any? = nil, _ arg3: @autoclosure ()->Any? = nil, _ arg4: @autoclosure ()->Any? = nil, _ arg5: @autoclosure ()->Any? = nil) {
	if Settings.logActivityToConsole {
        let message = String(format: message,
                             String(describing: arg1() ?? "(nil)"),
                             String(describing: arg2() ?? "(nil)"),
                             String(describing: arg3() ?? "(nil)"),
                             String(describing: arg4() ?? "(nil)"),
                             String(describing: arg5() ?? "(nil)"))
        #if DEBUG
        print(">>>", message)
        #else
        NSLog(message)
        #endif
	}
}

let numberFormatter: NumberFormatter = {
	let n = NumberFormatter()
	n.numberStyle = .decimal
	return n
}()

func bootUp() {
	Settings.checkMigration()
	DataManager.checkMigration()
	API.setup()
}

//////////////////////// Enums

enum ItemCondition: Int64 {
	case open, closed, merged

	static private var predicateMatchCache = [ItemCondition : NSPredicate]()
	var matchingPredicate: NSPredicate {
		if let predicate = ItemCondition.predicateMatchCache[self] {
			return predicate
		}
		let predicate = NSPredicate(format: "condition == \(rawValue)")
		ItemCondition.predicateMatchCache[self] = predicate
		return predicate
	}
	static private var predicateExcludeCache = [ItemCondition : NSPredicate]()
	var excludingPredicate: NSPredicate {
		if let predicate = ItemCondition.predicateExcludeCache[self] {
			return predicate
		}
		let predicate = NSPredicate(format: "condition != \(rawValue)")
		ItemCondition.predicateExcludeCache[self] = predicate
		return predicate
	}
}

enum StatusFilter: Int {
	case all, include, exclude
}

enum PostSyncAction: Int64 {
	case doNothing, delete, isNew, isUpdated

	static private var predicateMatchCache = [PostSyncAction : NSPredicate]()
	var matchingPredicate: NSPredicate {
		if let predicate = PostSyncAction.predicateMatchCache[self] {
			return predicate
		}
		let predicate = NSPredicate(format: "postSyncAction == %lld", rawValue)
		PostSyncAction.predicateMatchCache[self] = predicate
		return predicate
	}
	static private var predicateExcludeCache = [PostSyncAction : NSPredicate]()
	var excludingPredicate: NSPredicate {
		if let predicate = PostSyncAction.predicateExcludeCache[self] {
			return predicate
		}
		let predicate = NSPredicate(format: "postSyncAction != %lld", rawValue)
		PostSyncAction.predicateExcludeCache[self] = predicate
		return predicate
	}
}

enum NotificationType: Int {
	case newComment, newPr, prMerged, prReopened, newMention, prClosed, newRepoSubscribed, newRepoAnnouncement, newPrAssigned, newStatus, newIssue, issueClosed, newIssueAssigned, issueReopened, assignedForReview, changesRequested, changesApproved, changesDismissed, newReaction
}

enum SortingMethod: Int {
	case creationDate, recentActivity, title, linesAdded, linesRemoved
    static let reverseTitles = ["Youngest first", "Most recently active", "Reverse alphabetically", "Most lines added", "Most lines removed"]
	static let normalTitles = ["Oldest first", "Inactive for longest", "Alphabetically", "Least lines added", "Least lines removed"]

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
        case .linesAdded: return "linesAdded"
        case .linesRemoved: return "linesRemoved"
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

enum RepoDisplayPolicy: Int64, CaseIterable {
	case hide = 0
    case mine = 1
    case mineAndPaticipated = 2
    case all = 3
    case authoredOnly = 4
    
    static var labels: [String] {
        return self.allCases.map { $0.name }
    }
    	                         
	var name: String {
        switch self {
        case .hide:
            return "Hide"
        case .mine:
            return "Mine"
        case .mineAndPaticipated:
            return "Participated"
        case .all:
            return "All"
        case .authoredOnly:
            return "Authored"
        }
	}
    var bold: Bool {
        switch self {
        case .hide, .authoredOnly:
            return false
        default:
            return true
        }
    }
    var selectable: Bool {
        switch self {
        case .authoredOnly:
            return false
        default:
            return true
        }
    }
    var color: COLOR_CLASS {
        switch self {
        case .hide:
            return COLOR_CLASS.appTertiaryLabel
        case .authoredOnly:
            return COLOR_CLASS.appLabel
        case .mine:
            return COLOR_CLASS(red: 0.7, green: 0.0, blue: 0.0, alpha: 1.0)
        case .mineAndPaticipated:
            return COLOR_CLASS(red: 0.8, green: 0.4, blue: 0.0, alpha: 1.0)
        case .all:
            return COLOR_CLASS(red: 0.0, green: 0.5, blue: 0.0, alpha: 1.0)
        }
	}
	var intValue: Int { return Int(rawValue) }

	init?(_ rawValue: Int64) {
		self.init(rawValue: rawValue)
	}
	init?(_ rawValue: Int) {
		self.init(rawValue: Int64(rawValue))
	}
}

enum DraftHandlingPolicy: Int {
    case nothing, display, hide
    static let labels = ["Do Nothing", "Display in Title", "Hide"]
}

enum RepoHidingPolicy: Int64 {
	case noHiding, hideMyAuthoredPrs, hideMyAuthoredIssues, hideAllMyAuthoredItems, hideOthersPrs, hideOthersIssues, hideAllOthersItems
	static let labels = ["No Filter", "Hide My PRs", "Hide My Issues", "Hide All Mine", "Hide Others PRs", "Hide Others Issues", "Hide All Others"]
	static let policies = [noHiding, hideMyAuthoredPrs, hideMyAuthoredIssues, hideAllMyAuthoredItems, hideOthersPrs, hideOthersIssues, hideAllOthersItems]
	static let colors = [    COLOR_CLASS.appTertiaryLabel,
	                         COLOR_CLASS(red: 0.1, green: 0.1, blue: 0.5, alpha: 1.0),
	                         COLOR_CLASS(red: 0.1, green: 0.1, blue: 0.5, alpha: 1.0),
	                         COLOR_CLASS(red: 0.1, green: 0.1, blue: 0.5, alpha: 1.0),
	                         COLOR_CLASS(red: 0.5, green: 0.1, blue: 0.1, alpha: 1.0),
	                         COLOR_CLASS(red: 0.5, green: 0.1, blue: 0.1, alpha: 1.0),
	                         COLOR_CLASS(red: 0.5, green: 0.1, blue: 0.1, alpha: 1.0)]
	var name: String {
		return RepoHidingPolicy.labels[Int(rawValue)]
	}
    var bold: Bool {
        switch self {
        case .noHiding:
            return false
        default:
            return true
        }
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

let apiDateFormatter: DateFormatter = {
    let d = DateFormatter()
    d.timeZone = TimeZone(abbreviation: "UTC")
    d.locale = Locale(identifier: "en_US")
    d.dateFormat =  "yyyy-MM-dd'T'HH:mm:ss'Z'"
    return d
}()

struct ApiStats {
	let nodeCount, cost, remaining, limit: Int64
	let resetAt: Date?

	static func fromV3(headers: [AnyHashable : Any]) -> ApiStats {
		let date: Date?
		if let epochSeconds = headers["X-RateLimit-Reset"] as? String, let t = TimeInterval(epochSeconds) {
			date = Date(timeIntervalSince1970: t)
		} else {
			date = nil
		}
        return ApiStats(nodeCount: 0,
                             cost: 1,
                             remaining: Int64(S(headers["X-RateLimit-Remaining"] as? String)) ?? 10000,
                             limit: Int64(S(headers["X-RateLimit-Limit"] as? String)) ?? 10000,
                             resetAt: date)
	}
    
    static func fromV4(json: [AnyHashable : Any]?) -> ApiStats? {
        guard let info = json?["rateLimit"] as? [AnyHashable: Any] else { return nil }
        let date = apiDateFormatter.date(from: info["resetAt"] as? String ?? "")
        return ApiStats(nodeCount: info["nodeCount"] as? Int64 ?? 0,
                             cost: info["cost"] as? Int64 ?? 0,
                             remaining: info["remaining"] as? Int64 ?? 10000,
                             limit: info["limit"] as? Int64 ?? 10000,
                             resetAt: date)
    }
    
	static var noLimits: ApiStats {
        return ApiStats(nodeCount: 0, cost: 0, remaining: 10000, limit: 10000, resetAt: nil)
	}
    
	var areValid: Bool {
		return remaining >= 0
	}
}

var currentAppVersion: String {
	return S(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
}

var versionString: String {
	let buildNumber = S(Bundle.main.infoDictionary?["CFBundleVersion"] as? String)
	return "Version \(currentAppVersion) (\(buildNumber))"
}

#if os(OSX)

func openItem(_ url: URL) {
	openURL(url, using: Settings.defaultAppForOpeningItems.trim)
}

func openLink(_ url: URL) {
	openURL(url, using: Settings.defaultAppForOpeningWeb.trim)
}

func openURL(_ url: URL, using path: String) {
	if path.isEmpty {
		NSWorkspace.shared.open(url)
	} else {
		let appURL = URL(fileURLWithPath: path)
		do {
			try NSWorkspace.shared.open([url], withApplicationAt: appURL, options: [], configuration: [:])
		} catch {
			let a = NSAlert()
			a.alertStyle = .warning
			a.messageText = "Could not open this URL using '\(path)'"
			a.informativeText = error.localizedDescription
			a.runModal()
		}
	}
}

#endif

////////////////////// Notifications

extension Notification.Name {
    static let RefreshStarting = Notification.Name("RefreshStartingNotification")
    static let RefreshEnded = Notification.Name("RefreshEndedNotification")
    static let SyncProgressUpdate = Notification.Name("SyncProgressUpdateNotification")
    static let ApiUsageUpdate = Notification.Name("ApiUsageUpdateNotification")
    static let SettingsExported = Notification.Name("SettingsExportedNotification")
}
