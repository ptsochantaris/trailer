
enum Section: Int {
	case None, Mine, Participated, Mentioned, Merged, Closed, All, Snoozed
	static let prMenuTitles = ["", "Mine", "Participated", "Mentioned", "Recently Merged", "Recently Closed", "All Pull Requests", "Snoozed"]
	func prMenuName() -> String { return Section.prMenuTitles[rawValue] }

	static let issueMenuTitles = ["", "Mine", "Participated", "Mentioned", "Recently Merged", "Recently Closed", "All Issues", "Snoozed"]
	func issuesMenuName() -> String { return Section.issueMenuTitles[rawValue] }

	static let watchMenuTitles = ["", "Mine", "Participated", "Mentioned", "Merged", "Closed", "Other", "Snoozed"]
	func watchMenuName() -> String { return Section.watchMenuTitles[rawValue] }

	static let apiTitles = ["", "mine", "participated", "mentioned", "merged", "closed", "other", "snoozed"]
	func apiName() -> String { return Section.apiTitles[rawValue] }
}

func never() -> NSDate {
	return NSDate.distantPast()
}

func S(s: String?) -> String {
	return s ?? ""
}

typealias Completion = ()->Void

let shortDateFormatter = { () -> NSDateFormatter in
	let d = NSDateFormatter()
	d.dateStyle = .ShortStyle
	d.timeStyle = .ShortStyle
	d.doesRelativeDateFormatting = true
	return d
}()

////

func atNextEvent(completion: Completion) {
	NSOperationQueue.mainQueue().addOperationWithBlock(completion)
}

func atNextEvent<T: AnyObject>(owner: T?, completion: (T)->Void) {
	if let o = owner {
		atNextEvent(o, completion: completion)
	}
}

func atNextEvent<T: AnyObject>(owner: T, completion: (T)->Void) {
	NSOperationQueue.mainQueue().addOperationWithBlock { [weak owner] in
		if let o = owner {
			completion(o)
		}
	}
}

////

func delay(delay: NSTimeInterval, closure: Completion) {
	let time = dispatch_time(DISPATCH_TIME_NOW, Int64(delay * Double(NSEC_PER_SEC)))
	dispatch_after(time, dispatch_get_main_queue()) {
		atNextEvent(closure)
	}
}

func delay<T: AnyObject>(time: NSTimeInterval, _ owner: T, completion: (T)->()) {
	let time = dispatch_time(DISPATCH_TIME_NOW, Int64(time * Double(NSEC_PER_SEC)))
	dispatch_after(time, dispatch_get_main_queue()) { [weak owner] in
		atNextEvent { [weak owner] in
			if let o = owner {
				completion(o)
			}
		}
	}
}
