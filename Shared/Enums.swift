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
             containsLabel, containsAllLabels, containsAuthor, wasUncommented, hidingDrafts, assignedDirectReview,
             assignedTeamReview, hidingMyAuthoredPrs, repoShowMineAndParticipated, repoHideAllItems,
             repoShowMineOnly, doesntContainLabel, doesntContainAllLabels, doesntContainAuthor

        var description: String {
            switch self {
            case .unknown: "Unknown reason"

            case .hidingAllMyAuthoredItems: "Repo setting: Item authored by me"
            case .hidingMyAuthoredIssues: "IRepo setting: ssue authored by me"
            case .hidingAllOthersItems: "Repo setting: Item not authored by me"
            case .hidingOthersIssues: "Repo setting: Issue authored by others"
            case .hidingOthersPrs: "Repo setting: PR authored by others"
            case .hidingDrafts: "Display setting: Is marked as being a draft"

            case .containsLabel: "Blocked item: Label excluded"
            case .containsAllLabels: "Blocked item: All labels excluded"
            case .doesntContainLabel: "Blocked item: Doesn't contain label"
            case .doesntContainAllLabels: "Blocked item: Doesn't contain all labels"

            case .containsAuthor: "Blocked item: Author excluded"
            case .doesntContainAuthor: "Blocked item: Author required"

            case .wasUncommented: "Comment setting: Does not have any comments"

            case .assignedDirectReview: "Review setting: Assigned section based on direct review"
            case .assignedTeamReview: "Review setting: Assigned section based on team review"
            case .approvedByMe: "Review setting: Approved by me"
            case .rejectedByMe: "Review setting: Rejected by me"
            case .containsNonGreenStatuses: "Review setting: PR statuses aren't all green"

            case .hidingMyAuthoredPrs: "Repo setting: PR authored by me"
            case .repoShowMineAndParticipated: "Repo setting: Only Mine and Participated sections allowed"
            case .repoHideAllItems: "Repo setting: All items hidden"
            case .repoShowMineOnly: "Repo setting: Mine section items hidden"
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
        case .hidden: ""
        case .mine: "Mine"
        case .participated: "Participated"
        case .mentioned: "Mentioned"
        case .merged: "Recently Merged"
        case .closed: "Recently Closed"
        case .all: "All Pull Requests"
        case .snoozed: "Snoozed"
        }
    }

    var issuesMenuName: String {
        switch self {
        case .hidden: ""
        case .mine: "Mine"
        case .participated: "Participated"
        case .mentioned: "Mentioned"
        case .merged: "Recently Merged"
        case .closed: "Recently Closed"
        case .all: "All Issues"
        case .snoozed: "Snoozed"
        }
    }

    var watchMenuName: String {
        switch self {
        case .hidden: ""
        case .mine: "Mine"
        case .participated: "Participated"
        case .mentioned: "Mentioned"
        case .merged: "Merged"
        case .closed: "Closed"
        case .all: "Other"
        case .snoozed: "Snoozed"
        }
    }

    var apiName: String {
        switch self {
        case .hidden: ""
        case .mine: "mine"
        case .participated: "participated"
        case .mentioned: "mentioned"
        case .merged: "merged"
        case .closed: "closed"
        case .all: "other"
        case .snoozed: "snoozed"
        }
    }

    var sectionIndex: Int {
        switch self {
        case .hidden: 0
        case .mine: 1
        case .participated: 2
        case .mentioned: 3
        case .merged: 4
        case .closed: 5
        case .all: 6
        case .snoozed: 7
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

    private static let matchingPredicates = ContiguousArray((0 ... 7).map { NSPredicate(format: "sectionIndex == \($0)") })
    var matchingPredicate: NSPredicate {
        Section.matchingPredicates[sectionIndex]
    }

    private static let excludePredicates = ContiguousArray((0 ... 7).map { NSPredicate(format: "sectionIndex != \($0)") })
    var excludingPredicate: NSPredicate {
        Section.excludePredicates[sectionIndex]
    }

    ///////////////////////////////////////////////////////////

    static let assignmentPlacementLabels = [Section.mine.placementName,
                                            Section.participated.placementName,
                                            Section.mentioned.placementName,
                                            Section.hidden(cause: .unknown).placementName]

    static let movePlacementLabels = [Section.hidden(cause: .unknown).placementName,
                                      Section.mine.placementName,
                                      Section.participated.placementName,
                                      Section.mentioned.placementName]

    var placementName: String {
        switch self {
        case .mine:
            "Move to \"Mine\""
        case .mentioned:
            "Move to \"Mentioned\""
        case .participated:
            "Move to \"Participated\""
        default:
            "Do Nothing"
        }
    }

    var preferredSection: Section? {
        switch self {
        case .mentioned, .mine, .participated:
            self
        default:
            nil
        }
    }

    var assignmentPolicySettingsValue: Int {
        switch self {
        case .mine:
            0
        case .participated:
            1
        case .mentioned:
            3
        default:
            2
        }
    }

    var assignmentPolicyMenuIndex: Int {
        switch self {
        case .mine:
            0
        case .participated:
            1
        case .mentioned:
            2
        default:
            3
        }
    }

    init(assignmentPolicyMenuIndex: Int) {
        switch assignmentPolicyMenuIndex {
        case Section.mine.assignmentPolicyMenuIndex:
            self = .mine
        case Section.participated.assignmentPolicyMenuIndex:
            self = .participated
        case Section.mentioned.assignmentPolicyMenuIndex:
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
        case .mine: 1
        case .participated: 2
        case .mentioned: 3
        default: 0
        }
    }

    var movePolicyMenuIndex: Int {
        switch self {
        case .mine:
            1
        case .participated:
            2
        case .mentioned:
            3
        default:
            0
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
