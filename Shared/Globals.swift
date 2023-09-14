#if os(iOS)

    import CoreData
    import UIKit

    @MainActor weak var app: iOSAppDelegate!

    let GLOBAL_SCREEN_SCALE = UIScreen.main.scale
    let DISABLED_FADE: CGFloat = 0.3

    typealias FONT_CLASS = UIFont
    typealias IMAGE_CLASS = UIImage

    let stringDrawingOptions: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

    func makeKeyCommand(input: String, modifierFlags: UIKeyModifierFlags, action: Selector, discoverabilityTitle: String) -> UIKeyCommand {
        UIKeyCommand(title: discoverabilityTitle, image: nil, action: action, input: input, modifierFlags: modifierFlags, propertyList: nil, alternates: [], discoverabilityTitle: nil, attributes: [], state: .off)
    }

    let compactTraits = UITraitCollection(horizontalSizeClass: .compact)

#elseif os(macOS)

    @MainActor weak var app: MacAppDelegate!

    let AVATAR_SIZE: CGFloat = 26
    let AVATAR_PADDING: CGFloat = 8
    let LEFTPADDING: CGFloat = 44
    let MENU_WIDTH: CGFloat = 500
    let REMOVE_BUTTON_WIDTH: CGFloat = 80
    let DISABLED_FADE: CGFloat = 0.4

    import Cocoa

    typealias FONT_CLASS = NSFont
    typealias IMAGE_CLASS = NSImage

    let stringDrawingOptions: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

#endif

extension NSAttributedString.Key {
    static let trailerTagBackgroundColour = NSAttributedString.Key("trailerTagBackgroundColour")
}

import KeyVine
var keyVine = KeyVine(appIdentifier: "com.housetrip.Trailer", teamId: "X727JSJUGJ")

@MainActor var preferencesDirty = false
@MainActor var lastRepoCheck = Date.distantPast
let autoSnoozeSentinelDate = Date.distantFuture.addingTimeInterval(-1)
let LISTABLE_URI_KEY = "listableUriKey"
let COMMENT_ID_KEY = "commentIdKey"
let NOTIFICATION_URL_KEY = "urlKey"

extension NSAttributedString: @unchecked Sendable {}
extension IMAGE_CLASS: @unchecked Sendable {}

////////////////////////// Utilities

#if os(iOS)

    @MainActor
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

let itemDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    f.doesRelativeDateFormatting = true
    return f
}()

let numberFormatter: NumberFormatter = {
    let n = NumberFormatter()
    n.numberStyle = .decimal
    return n
}()

@MainActor
func bootUp() {
    if CommandLine.arguments.contains("-useSystemLog") {
        Logging.setupConsoleLogging()
    }

    Settings.checkMigration()
    DataManager.checkMigration()
    API.setup()
}

//////////////////////// Enums

enum ItemCondition: Int {
    case open, closed, merged

    private static let matchingPredicates = ContiguousArray((0 ... 2).map { NSPredicate(format: "condition == \($0)") })
    var matchingPredicate: NSPredicate { ItemCondition.matchingPredicates[rawValue] }

    private static let excludingPredicates = ContiguousArray((0 ... 2).map { NSPredicate(format: "condition != \($0)") })
    var excludingPredicate: NSPredicate { ItemCondition.excludingPredicates[rawValue] }
}

enum StatusFilter: Int {
    case all, include, exclude
}

enum PostSyncAction: Int {
    case doNothing, delete, isNew, isUpdated

    private static let matchingPredicates = ContiguousArray((0 ... 3).map { NSPredicate(format: "postSyncAction == \($0)") })
    var matchingPredicate: NSPredicate { PostSyncAction.matchingPredicates[rawValue] }

    private static let excludingPredicates = ContiguousArray((0 ... 3).map { NSPredicate(format: "postSyncAction != \($0)") })
    var excludingPredicate: NSPredicate { PostSyncAction.excludingPredicates[rawValue] }
}

enum NotificationType {
    case newComment, newPr, prMerged, prReopened, newMention, prClosed, newRepoSubscribed, newRepoAnnouncement, newPrAssigned, newStatus, newIssue, issueClosed, newIssueAssigned, issueReopened, assignedForReview, changesRequested, changesApproved, changesDismissed, newReaction, assignedToTeamForReview
}

enum SortingMethod: Int, CaseIterable {
    case creationDate, recentActivity, title, linesAdded, linesRemoved

    var normalTitle: String {
        switch self {
        case .creationDate: "Oldest first"
        case .recentActivity: "Inactive for longest"
        case .title: "Alphabetically"
        case .linesAdded: "Least lines added"
        case .linesRemoved: "Least lines removed"
        }
    }

    var reverseTitle: String {
        switch self {
        case .creationDate: "Youngest first"
        case .recentActivity: "Most recently active"
        case .title: "Reverse alphabetically"
        case .linesAdded: "Most lines added"
        case .linesRemoved: "Most lines removed"
        }
    }

    var field: String? {
        switch self {
        case .creationDate: "createdAt"
        case .recentActivity: "updatedAt"
        case .title: "title"
        case .linesAdded: "linesAdded"
        case .linesRemoved: "linesRemoved"
        }
    }
}

enum KeepPolicy: Int {
    case mine, mineAndParticipated, everything, nothing
    static let labels = ["Keep Mine", "Keep Mine & Participated", "Keep All", "Don't Keep"]
    var name: String {
        KeepPolicy.labels[rawValue]
    }
}

enum RepoDisplayPolicy: Int, CaseIterable {
    case hide, mine, mineAndPaticipated, all, authoredOnly

    static var labels: [String] = allCases.map(\.name)

    var name: String {
        switch self {
        case .hide:
            "Hide"
        case .mine:
            "Mine"
        case .mineAndPaticipated:
            "Participated"
        case .all:
            "All"
        case .authoredOnly:
            "Authored"
        }
    }

    var bold: Bool {
        switch self {
        case .authoredOnly, .hide:
            false
        default:
            true
        }
    }

    var selectable: Bool {
        switch self {
        case .authoredOnly:
            false
        default:
            true
        }
    }

    var color: COLOR_CLASS {
        switch self {
        case .hide:
            COLOR_CLASS.appTertiaryLabel
        case .authoredOnly:
            COLOR_CLASS.appLabel
        case .mine:
            COLOR_CLASS(red: 0.7, green: 0.0, blue: 0.0, alpha: 1.0)
        case .mineAndPaticipated:
            COLOR_CLASS(red: 0.8, green: 0.4, blue: 0.0, alpha: 1.0)
        case .all:
            COLOR_CLASS(red: 0.0, green: 0.5, blue: 0.0, alpha: 1.0)
        }
    }

    var intValue: Int { Int(rawValue) }
}

enum DraftHandlingPolicy: Int, CaseIterable {
    case nothing, display, hide

    static let allCases: [DraftHandlingPolicy] = [.nothing, .display, .hide]

    var label: String {
        switch self {
        case .nothing: "Do Nothing"
        case .display: "Display in Title"
        case .hide: "Hide"
        }
    }
}

enum AssignmentStatus: Int {
    case none, me, myTeam, others

    var assignedStatus: AssignmentStatus? {
        switch self {
        case .none, .others:
            nil
        case .me, .myTeam:
            self
        }
    }
}

enum RepoHidingPolicy: Int {
    case noHiding, hideMyAuthoredPrs, hideMyAuthoredIssues, hideAllMyAuthoredItems, hideOthersPrs, hideOthersIssues, hideAllOthersItems
    static let labels = ["No Filter", "Hide My PRs", "Hide My Issues", "Hide All Mine", "Hide Others PRs", "Hide Others Issues", "Hide All Others"]
    static let policies = [noHiding, hideMyAuthoredPrs, hideMyAuthoredIssues, hideAllMyAuthoredItems, hideOthersPrs, hideOthersIssues, hideAllOthersItems]
    static let colors = [COLOR_CLASS.appTertiaryLabel,
                         COLOR_CLASS(red: 0.1, green: 0.1, blue: 0.5, alpha: 1.0),
                         COLOR_CLASS(red: 0.1, green: 0.1, blue: 0.5, alpha: 1.0),
                         COLOR_CLASS(red: 0.1, green: 0.1, blue: 0.5, alpha: 1.0),
                         COLOR_CLASS(red: 0.5, green: 0.1, blue: 0.1, alpha: 1.0),
                         COLOR_CLASS(red: 0.5, green: 0.1, blue: 0.1, alpha: 1.0),
                         COLOR_CLASS(red: 0.5, green: 0.1, blue: 0.1, alpha: 1.0)]
    var name: String {
        RepoHidingPolicy.labels[rawValue]
    }

    var bold: Bool {
        switch self {
        case .noHiding:
            false
        default:
            true
        }
    }

    var color: COLOR_CLASS {
        RepoHidingPolicy.colors[rawValue]
    }
}

let apiDateFormatter: DateFormatter = {
    let d = DateFormatter()
    d.timeZone = TimeZone(abbreviation: "UTC")
    d.locale = Locale(identifier: "en_US")
    d.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
    return d
}()

struct ApiStats {
    let nodeCount, cost, remaining, limit: Int
    let resetAt: Date?
    let migratedIds: [String: String]?

    static func fromV3(headers: [AnyHashable: Any]) -> ApiStats {
        let date: Date?
        if let epochSeconds = headers["x-ratelimit-reset"] as? String, let t = TimeInterval(epochSeconds) {
            date = Date(timeIntervalSince1970: t)
        } else {
            date = nil
        }
        let remaining = Int(headers["x-ratelimit-remaining"].stringOrEmpty) ?? 10000
        let limit = Int(headers["x-ratelimit-limit"].stringOrEmpty) ?? 10000
        return ApiStats(nodeCount: 0, cost: 1, remaining: remaining, limit: limit, resetAt: date, migratedIds: nil)
    }

    static func fromV4(json: JSON?, migratedIds: [String: String]?) -> ApiStats? {
        guard let info = json?["rateLimit"] as? JSON else { return nil }
        let date = apiDateFormatter.date(from: info["resetAt"].stringOrEmpty)
        return ApiStats(nodeCount: info["nodeCount"] as? Int ?? 0,
                        cost: info["cost"] as? Int ?? 0,
                        remaining: info["remaining"] as? Int ?? 10000,
                        limit: info["limit"] as? Int ?? 10000,
                        resetAt: date,
                        migratedIds: migratedIds)
    }

    static var noLimits: ApiStats {
        ApiStats(nodeCount: 0, cost: 0, remaining: 10000, limit: 10000, resetAt: nil, migratedIds: nil)
    }

    var areValid: Bool {
        remaining >= 0
    }
}

let currentAppVersion: String = {
    (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).orEmpty
}()

let versionString: String = {
    let buildNumber = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String).orEmpty
    return "Version \(currentAppVersion) (\(buildNumber))"
}()

#if os(macOS)

    @MainActor
    func openItem(_ url: URL) {
        openURL(url, using: Settings.defaultAppForOpeningItems.trim)
    }

    @MainActor
    func openLink(_ url: URL) {
        openURL(url, using: Settings.defaultAppForOpeningWeb.trim)
    }

    func openURL(_ url: URL, using path: String) {
        if path.isEmpty {
            NSWorkspace.shared.open(url)
        } else {
            Task { @MainActor in
                let appURL = URL(fileURLWithPath: path)
                do {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                            if let error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume()
                            }
                        }
                    }
                } catch {
                    let a = NSAlert()
                    a.alertStyle = .warning
                    a.messageText = "Could not open this URL using '\(path)'"
                    a.informativeText = error.localizedDescription
                    a.runModal()
                }
            }
        }
    }

#endif

////////////////////// Notifications

extension Notification.Name {
    static let RefreshStarting = Notification.Name("RefreshStartingNotification")
    static let RefreshEnded = Notification.Name("RefreshEndedNotification")
    static let SyncProgressUpdate = Notification.Name("SyncProgressUpdateNotification")
    static let SettingsExported = Notification.Name("SettingsExportedNotification")
}
