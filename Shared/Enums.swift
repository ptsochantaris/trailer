
enum Section: Int {
	case none, mine, participated, mentioned, merged, closed, all, snoozed
	static let prMenuTitles = ["", "Mine", "Participated", "Mentioned", "Recently Merged", "Recently Closed", "All Pull Requests", "Snoozed"]
	func prMenuName() -> String { return Section.prMenuTitles[rawValue] }

	static let issueMenuTitles = ["", "Mine", "Participated", "Mentioned", "Recently Merged", "Recently Closed", "All Issues", "Snoozed"]
	func issuesMenuName() -> String { return Section.issueMenuTitles[rawValue] }

	static let watchMenuTitles = ["", "Mine", "Participated", "Mentioned", "Merged", "Closed", "Other", "Snoozed"]
	func watchMenuName() -> String { return Section.watchMenuTitles[rawValue] }

	static let apiTitles = ["", "mine", "participated", "mentioned", "merged", "closed", "other", "snoozed"]
	func apiName() -> String { return Section.apiTitles[rawValue] }

	static let movePolicyNames = ["Don't Move", "Mine", "Participated", "Mentioned"]
	func movePolicyName() -> String { return Section.movePolicyNames[rawValue] }
}

func S(_ s: String?) -> String {
	return s ?? ""
}

typealias Completion = ()->Void

let shortDateFormatter = { () -> DateFormatter in
	let d = DateFormatter()
	d.dateStyle = .short
	d.timeStyle = .short
	d.doesRelativeDateFormatting = true
	return d
}()

////

func atNextEvent(_ completion: Completion) {
	OperationQueue.main.addOperation(completion)
}

func atNextEvent<T: AnyObject>(_ owner: T?, completion: (T)->Void) {
	if let o = owner {
		atNextEvent(o, completion: completion)
	}
}

func atNextEvent<T: AnyObject>(_ owner: T, completion: (T)->Void) {
	OperationQueue.main.addOperation { [weak owner] in
		if let o = owner {
			completion(o)
		}
	}
}

////

func delay(_ delay: TimeInterval, closure: Completion) {
	let time = DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
	DispatchQueue.main.asyncAfter(deadline: time, execute: closure)
}

func delay<T: AnyObject>(_ time: TimeInterval, _ owner: T, completion: (T)->()) {
	let time = DispatchTime.now() + Double(Int64(time * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
	DispatchQueue.main.asyncAfter(deadline: time) { [weak owner] in
		atNextEvent { [weak owner] in
			if let o = owner {
				completion(o)
			}
		}
	}
}
