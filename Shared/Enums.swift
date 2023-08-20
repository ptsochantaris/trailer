import Foundation

extension Bool {
    var asInt: Int {
        self ? 1 : 0
    }
}

enum Section: CaseIterable, Equatable {
    enum HidingCause {
        case unknown, approvedByMe, rejectedByMe, hidingAllMyAuthoredItems,
             hidingMyAuthoredIssues, hidingAllOthersItems, hidingOthersIssues, containsNonGreenStatuses, hidingOthersPrs,
             containsBlockedLabel, containsBlockedAuthor, wasUncommented, hidingDrafts, assignedDirectReview,
             assignedTeamReview, hidingMyAuthoredPrs, repoShowMineAndParticipated, repoHideAllItems,
             repoShowMineOnly
        
        var description: String {
            switch self {
            case .unknown: return "Unknown reason"
                
            case .hidingAllMyAuthoredItems: return "Repo setting: Item authored by me"
            case .hidingMyAuthoredIssues: return "IRepo setting: ssue authored by me"
            case .hidingAllOthersItems: return "Repo setting: Item not authored by me"
            case .hidingOthersIssues: return "Repo setting: Issue authored by others"
            case .hidingOthersPrs: return "Repo setting: PR authored by others"
            case .hidingDrafts: return "Display setting: Is marked as being a draft"
                
            case .containsBlockedLabel: return "Blocked item: Label"
            case .containsBlockedAuthor: return "Blocked item: Author"
                
            case .wasUncommented: return "Comment setting: Does not have any comments"
                
            case .assignedDirectReview: return "Review setting: Assigned section based on direct review"
            case .assignedTeamReview: return "Review setting: Assigned section based on team review"
            case .approvedByMe: return "Review setting: Approved by me"
            case .rejectedByMe: return "Review setting: Rejected by me"
            case .containsNonGreenStatuses: return "Review setting: PR statuses aren't all green"
                
            case .hidingMyAuthoredPrs: return "Repo setting: PR authored by me"
            case .repoShowMineAndParticipated: return "Repo setting: Only Mine and Participated sections allowed"
            case .repoHideAllItems: return "Repo setting: All items hidden"
            case .repoShowMineOnly: return "Repo setting: Mine section items hidden"
            }
        }
    }

    case hidden(cause: HidingCause), mine, participated, mentioned, merged, closed, all, snoozed

    static let allCases: [Section] = [.hidden(cause: .unknown), .mine, .participated, .mentioned, .merged, .closed, .all, .snoozed]

    static func == (lhs: Section, rhs: Section) -> Bool {
        switch lhs {
        case .hidden:
            if case .hidden = rhs {
                return true
            }
            return false
        case .mine:
            if case .mine = rhs {
                return true
            }
            return false
        case .participated:
            if case .participated = rhs {
                return true
            }
            return false
        case .mentioned:
            if case .mentioned = rhs {
                return true
            }
            return false
        case .merged:
            if case .merged = rhs {
                return true
            }
            return false
        case .closed:
            if case .closed = rhs {
                return true
            }
            return false
        case .all:
            if case .all = rhs {
                return true
            }
            return false
        case .snoozed:
            if case .snoozed = rhs {
                return true
            }
            return false
        }
    }

    var visible: Bool {
        if case .hidden = self {
            return false
        }
        return true
    }

    var prMenuName: String {
        switch self {
        case .hidden: return ""
        case .mine: return "Mine"
        case .participated: return "Participated"
        case .mentioned: return "Mentioned"
        case .merged: return "Recently Merged"
        case .closed: return "Recently Closed"
        case .all: return "All Pull Requests"
        case .snoozed: return "Snoozed"
        }
    }

    var issuesMenuName: String {
        switch self {
        case .hidden: return ""
        case .mine: return "Mine"
        case .participated: return "Participated"
        case .mentioned: return "Mentioned"
        case .merged: return "Recently Merged"
        case .closed: return "Recently Closed"
        case .all: return "All Issues"
        case .snoozed: return "Snoozed"
        }
    }

    var watchMenuName: String {
        switch self {
        case .hidden: return ""
        case .mine: return "Mine"
        case .participated: return "Participated"
        case .mentioned: return "Mentioned"
        case .merged: return "Merged"
        case .closed: return "Closed"
        case .all: return "Other"
        case .snoozed: return "Snoozed"
        }
    }

    var apiName: String {
        switch self {
        case .hidden: return ""
        case .mine: return "mine"
        case .participated: return "participated"
        case .mentioned: return "mentioned"
        case .merged: return "merged"
        case .closed: return "closed"
        case .all: return "other"
        case .snoozed: return "snoozed"
        }
    }

    var sectionIndex: Int {
        switch self {
        case .hidden: return 0
        case .mine: return 1
        case .participated: return 2
        case .mentioned: return 3
        case .merged: return 4
        case .closed: return 5
        case .all: return 6
        case .snoozed: return 7
        }
    }

    init?(apiName: String) {
        if let section = Self.allCases.first(where: { $0.apiName == apiName }) {
            self = section
        } else {
            return nil
        }
    }

    init(sectionIndex: Int) {
        switch sectionIndex {
        case 1:
            self = .mine
        case 2:
            self = .participated
        case 3:
            self = .mentioned
        case 4:
            self = .merged
        case 5:
            self = .closed
        case 6:
            self = .all
        case 7:
            self = .snoozed
        default:
            self = .hidden(cause: .unknown)
        }
    }

    static let nonZeroPredicate = NSPredicate(format: "sectionIndex > 0")

    private static var predicateMatchCache = NSCache<NSNumber, NSPredicate>()
    var matchingPredicate: NSPredicate {
        let key = NSNumber(value: sectionIndex)
        if let predicate = Section.predicateMatchCache.object(forKey: key) {
            return predicate
        }
        let predicate = NSPredicate(format: "sectionIndex == %lld", sectionIndex)
        Section.predicateMatchCache.setObject(predicate, forKey: key)
        return predicate
    }

    private static var predicateExcludeCache = NSCache<NSNumber, NSPredicate>()
    var excludingPredicate: NSPredicate {
        let key = NSNumber(value: sectionIndex)
        if let predicate = Section.predicateExcludeCache.object(forKey: key) {
            return predicate
        }
        let predicate = NSPredicate(format: "sectionIndex != %lld", sectionIndex)
        Section.predicateExcludeCache.setObject(predicate, forKey: key)
        return predicate
    }

    ///////////////////////////////////////////////////////////

    static let placementLabels = [Section.mine.placementName,
                                  Section.participated.placementName,
                                  Section.mentioned.placementName,
                                  Section.hidden(cause: .unknown).placementName]

    var placementName: String {
        switch self {
        case .mine:
            return "Move to \"Mine\""
        case .mentioned:
            return "Move to \"Mentioned\""
        case .participated:
            return "Move to \"Participated\""
        default:
            return "Do Nothing"
        }
    }

    var preferredSection: Section? {
        switch self {
        case .mentioned, .mine, .participated:
            return self
        default:
            return nil
        }
    }

    var assignmentPolicySettingsValue: Int {
        switch self {
        case .mine:
            return 0
        case .participated:
            return 1
        case .mentioned:
            return 3
        default:
            return 2
        }
    }

    var assignmentPolictMenuIndex: Int {
        switch self {
        case .mine:
            return 0
        case .participated:
            return 1
        case .mentioned:
            return 2
        default:
            return 3
        }
    }

    init(assignmentPolicyMenuIndex: Int) {
        switch assignmentPolicyMenuIndex {
        case Section.mine.assignmentPolictMenuIndex:
            self = .mine
        case Section.participated.assignmentPolictMenuIndex:
            self = .participated
        case Section.mentioned.assignmentPolictMenuIndex:
            self = .mentioned
        default:
            self = .hidden(cause: .unknown)
        }
    }

    init(assignmentPolicySettingsValue: Int) {
        switch assignmentPolicySettingsValue {
        case 2: self = .hidden(cause: .unknown)
        case 1: self = .participated
        case 3: self = .mentioned
        default: self = .mine
        }
    }

    var movePolicySettingsValue: Int {
        switch self {
        case .mine: return 1
        case .participated: return 2
        case .mentioned: return 3
        default: return 0
        }
    }

    var movePolicyMenuIndex: Int {
        switch self {
        case .mine:
            return 1
        case .participated:
            return 2
        case .mentioned:
            return 3
        default:
            return 0
        }
    }

    init(movePolicyMenuIndex: Int) {
        switch movePolicyMenuIndex {
        case 1: self = .mine
        case 2: self = .participated
        case 3: self = .mentioned
        default: self = .hidden(cause: .unknown)
        }
    }

    init(movePolicySettingsValue: Int) {
        switch movePolicySettingsValue {
        case 1: self = .mine
        case 2: self = .participated
        case 3: self = .mentioned
        default: self = .hidden(cause: .unknown)
        }
    }
}

extension String? {
    var isEmpty: Bool {
        orEmpty.isEmpty
    }

    var orEmpty: String {
        self ?? ""
    }
}

extension Any? {
    var stringOrEmpty: String {
        (self as? String).orEmpty
    }
}

let shortDateFormatter: DateFormatter = {
    let d = DateFormatter()
    d.dateStyle = .short
    d.timeStyle = .short
    d.doesRelativeDateFormatting = true
    return d
}()

private let agoFormatter: DateComponentsFormatter = {
    let f = DateComponentsFormatter()
    f.allowedUnits = [.year, .month, .day, .hour, .minute, .second]
    f.unitsStyle = .abbreviated
    f.collapsesLargestUnit = true
    f.maximumUnitCount = 2
    return f
}()

func agoFormat(prefix: String, since: Date?) -> String {
    guard let since, since != .distantPast else {
        return "Not \(prefix.lowercased()) yet"
    }

    let now = Date()
    if now.timeIntervalSince(since) < 3 {
        return "\(prefix) just now"
    }
    let duration = agoFormatter.string(from: since, to: now) ?? "unknown time"
    return "\(prefix) \(duration) ago"
}

////

extension String {
    var trim: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var capitalFirstLetter: String {
        if !isEmpty {
            return prefix(1).uppercased() + dropFirst()
        }
        return self
    }

    func appending(pathComponent: String) -> String {
        let endSlash = hasSuffix("/")
        let firstSlash = pathComponent.hasPrefix("/")
        if endSlash, firstSlash {
            return appending(pathComponent.dropFirst())
        } else if !endSlash, !firstSlash {
            return appending("/\(pathComponent)")
        } else {
            return appending(pathComponent)
        }
    }

    var comparableForm: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
