
kPullRequestSectionNames = ["", "Mine", "Participated", "Recently Merged", "Recently Closed", "All Pull Requests"]
currentAppVersion = NSBundle.mainBundle().infoDictionary!["CFBundleShortVersionString"] as String
DataManager.checkMigration()
api = API()

//debugging sections
//let prs = PullRequest.allItemsOfType("PullRequest", inMoc: mainObjectContext) as [PullRequest]
//prs[0].condition = NSNumber(integer: PullRequestCondition.Merged.rawValue)
//prs[1].condition = NSNumber(integer: PullRequestCondition.Closed.rawValue)
//prs[2].condition = NSNumber(integer: PullRequestCondition.Merged.rawValue)
//prs[3].condition = NSNumber(integer: PullRequestCondition.Closed.rawValue)

#if os(iOS)
	UIApplicationMain(C_ARGC, C_ARGV, nil, NSStringFromClass(iOS_AppDelegate));
#else
	NSApplicationMain(C_ARGC, C_ARGV)
#endif
