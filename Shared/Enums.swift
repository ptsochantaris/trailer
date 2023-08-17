import Foundation

enum Section: CaseIterable {
    case none, mine, participated, mentioned, merged, closed, all, snoozed

    static let allCases: [Section] = [.none, .mine, .participated, .mentioned, .merged, .closed, .all, .snoozed]

    var prMenuName: String {
        switch self {
        case .none: return ""
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
        case .none: return ""
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
        case .none: return ""
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
        case .none: return ""
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
        case .none: return 0
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
            self = .none
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
                                  Section.none.placementName]

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
            self = .none
        }
    }

    init(assignmentPolicySettingsValue: Int) {
        switch assignmentPolicySettingsValue {
        case 2: self = .none
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
        default: self = .none
        }
    }

    init(movePolicySettingsValue: Int) {
        switch movePolicySettingsValue {
        case 1: self = .mine
        case 2: self = .participated
        case 3: self = .mentioned
        default: self = .none
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
