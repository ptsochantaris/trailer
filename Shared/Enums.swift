
enum PullRequestSection: Int {
	case None, Mine, Participated, Merged, Closed, All
	static let prMenuTitles = ["", "Mine", "Participated", "Recently Merged", "Recently Closed", "All Pull Requests"]
	static let issueMenuTitles = ["", "Mine", "Participated", "Recently Merged", "Recently Closed", "All Issues"]
	static let watchMenuTitles = ["", "Mine", "Participated", "Merged", "Closed", "Other"]
	static let apiTitles = ["", "mine", "participated", "merged", "closed", "other"]
	func prMenuName() -> String {
		return PullRequestSection.prMenuTitles[rawValue]
	}
	func issuesMenuName() -> String {
		return PullRequestSection.issueMenuTitles[rawValue]
	}
	func watchMenuName() -> String {
		return PullRequestSection.watchMenuTitles[rawValue]
	}
	func apiName() -> String {
		return PullRequestSection.apiTitles[rawValue]
	}
}
func sectionFromApi(apiName: String) -> PullRequestSection {
	return PullRequestSection(rawValue: PullRequestSection.apiTitles.indexOf(apiName)!)!
}

func never() -> NSDate {
	return NSDate.distantPast()
}

typealias Completion = ()->Void

func atNextEvent(completion: Completion) {
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (Int64)(0.1 * Double(NSEC_PER_SEC))), dispatch_get_main_queue()) {
		completion()
	}
}
