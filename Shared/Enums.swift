
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

	static private var predicateMatchCache = [Section : NSPredicate]()
	var matchingPredicate: NSPredicate {
		if let predicate = Section.predicateMatchCache[self] {
			return predicate
		}
		let predicate = NSPredicate(format: "sectionIndex == %lld", rawValue)
		Section.predicateMatchCache[self] = predicate
		return predicate
	}
	static private var predicateExcludeCache = [Section : NSPredicate]()
	var excludingPredicate: NSPredicate {
		if let predicate = Section.predicateExcludeCache[self] {
			return predicate
		}
		let predicate = NSPredicate(format: "sectionIndex != %lld", rawValue)
		Section.predicateExcludeCache[self] = predicate
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
	f.allowedUnits = [.year, .month, .day, .hour, .minute]
	f.unitsStyle = .abbreviated
	return f
}()

func agoFormat(prefix: String, since: Date?) -> String {

	guard let since = since, since != .distantPast else {
		return "not \(prefix) yet"
	}

	let interval = -since.timeIntervalSinceNow
	if interval < 60.0 {
		return "\(prefix) just now"
	} else {
		let duration = agoFormatter.string(from: since, to: Date()) ?? "unknown time"
		return "\(prefix) \(duration) ago"
	}
}

////

func atNextEvent(_ completion: @escaping Completion) {
	OperationQueue.main.addOperation(completion)
}

func atNextEvent<T: AnyObject>(_ owner: T?, completion: @escaping (T)->Void) {
	if let o = owner {
		atNextEvent(o, completion: completion)
	}
}

func atNextEvent<T: AnyObject>(_ owner: T, completion: @escaping (T)->Void) {
	atNextEvent { [weak owner] in
		if let o = owner {
			completion(o)
		}
	}
}

////

func delay(_ delay: TimeInterval, closure: @escaping Completion) {
	let time = DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
	DispatchQueue.main.asyncAfter(deadline: time, execute: closure)
}

func delay<T: AnyObject>(_ time: TimeInterval, _ owner: T, completion: @escaping (T) -> Void) {
	let time = DispatchTime.now() + Double(Int64(time * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
	DispatchQueue.main.asyncAfter(deadline: time) { [weak owner] in
		atNextEvent { [weak owner] in
			if let o = owner {
				completion(o)
			}
		}
	}
}
