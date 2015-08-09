
enum PullRequestCondition: Int {
	case Open, Closed, Merged
}

enum PullRequestSection: Int {
	case None, Mine, Participated, Merged, Closed, All
	static let prMenuTitles = ["", "Mine", "Participated", "Recently Merged", "Recently Closed", "All Pull Requests"]
	static let issueMenuTitles = ["", "Mine", "Participated", "Recently Merged", "Recently Closed", "All Issues"]
	static let watchMenuTitles = ["", "Mine", "Participated", "Merged", "Closed", "Other"]
	func prMenuName() -> String {
		return PullRequestSection.prMenuTitles[rawValue]
	}
	func issuesMenuName() -> String {
		return PullRequestSection.issueMenuTitles[rawValue]
	}
	func watchMenuName() -> String {
		return PullRequestSection.watchMenuTitles[rawValue]
	}
}

enum StatusFilter: Int {
	case All, Include, Exclude
}

enum PostSyncAction: Int {
	case DoNothing, Delete, NoteNew, NoteUpdated
}

enum PRNotificationType: Int {
	case NewComment, NewPr, PrMerged, PrReopened, NewMention, PrClosed, NewRepoSubscribed, NewRepoAnnouncement, NewPrAssigned, NewStatus, NewIssue, IssueClosed, NewIssueAssigned, IssueReopened
}

enum PRSortingMethod: Int {
	case CreationDate, RecentActivity, Title, Repository
}

enum PRHandlingPolicy: Int {
	case KeepMine, KeepMineAndParticipated, KeepAll, KeepNone
	static let labels = ["Keep Mine", "Keep Mine & Participated", "Keep All", "Don't Keep"]
	func name() -> String {
		return PRHandlingPolicy.labels[rawValue]
	}
}

enum PRAssignmentPolicy: Int {
	case MoveToMine, MoveToParticipated, DoNothing
	static let labels = ["Move To Mine", "Move To Participated", "Do Nothing"]
	func name() -> String {
		return PRAssignmentPolicy.labels[rawValue]
	}
}

enum RepoDisplayPolicy: Int {
	case Hide, Mine, MineAndPaticipated, All
	static let labels = ["Hide", "Mine", "Participated", "All"]
	func name() -> String {
		return RepoDisplayPolicy.labels[rawValue]
	}
}
