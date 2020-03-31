
import Foundation

enum Section: Int64 {
	case none, mine, participated, mentioned, merged, closed, all, snoozed
	static let prMenuTitles = ["", "Mine", "Participated", "Mentioned", "Recently Merged", "Recently Closed", "All Pull Requests", "Snoozed"]
	var prMenuName: String { return Section.prMenuTitles[Int(rawValue)] }

	static let issueMenuTitles = ["", "Mine", "Participated", "Mentioned", "Recently Merged", "Recently Closed", "All Issues", "Snoozed"]
	var issuesMenuName: String { return Section.issueMenuTitles[Int(rawValue)] }

	static let watchMenuTitles = ["", "Mine", "Participated", "Mentioned", "Merged", "Closed", "Other", "Snoozed"]
	var watchMenuName: String { return Section.watchMenuTitles[Int(rawValue)] }

	static let apiTitles = ["", "mine", "participated", "mentioned", "merged", "closed", "other", "snoozed"]
	var apiName: String { return Section.apiTitles[Int(rawValue)] }

	static let movePolicyNames = ["Don't Move", "Mine", "Participated", "Mentioned"]
	var movePolicyName: String { return Section.movePolicyNames[Int(rawValue)] }

	var isLoud: Bool {
		return self != .all && self != .snoozed && self != .none
	}

	var intValue: Int { return Int(rawValue) }

	init?(_ rawValue: Int) {
		self.init(rawValue: Int64(rawValue))
	}
	init?(_ rawValue: Int64) {
		self.init(rawValue: rawValue)
	}

	static let nonZeroPredicate = NSPredicate(format: "sectionIndex > 0")

	static private var predicateMatchCache = NSCache<NSNumber, NSPredicate>()
	var matchingPredicate: NSPredicate {
        let key = NSNumber(value: self.rawValue)
        if let predicate = Section.predicateMatchCache.object(forKey: key) {
			return predicate
		}
		let predicate = NSPredicate(format: "sectionIndex == %lld", rawValue)
        Section.predicateMatchCache.setObject(predicate, forKey: key)
		return predicate
	}
	static private var predicateExcludeCache = NSCache<NSNumber, NSPredicate>()
	var excludingPredicate: NSPredicate {
        let key = NSNumber(value: self.rawValue)
        if let predicate = Section.predicateExcludeCache.object(forKey: key) {
			return predicate
		}
		let predicate = NSPredicate(format: "sectionIndex != %lld", rawValue)
        Section.predicateExcludeCache.setObject(predicate, forKey: key)
		return predicate
	}
}

func S(_ s: String?) -> String {
	return s ?? ""
}

typealias Completion = () -> Void

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
	guard let since = since, since != .distantPast else {
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
        return trimmingCharacters(in: .whitespacesAndNewlines)
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
        if endSlash && firstSlash {
            return appending(pathComponent.dropFirst())
        } else if (!endSlash && !firstSlash) {
            return appending("/\(pathComponent)")
        } else {
            return appending(pathComponent)
        }
    }
}
