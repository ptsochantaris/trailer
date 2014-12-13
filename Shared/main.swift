
kPullRequestSectionNames = ["", "Mine", "Participated", "Recently Merged", "Recently Closed", "All Pull Requests"]
currentAppVersion = NSBundle.mainBundle().infoDictionary!["CFBundleShortVersionString"] as String
DataManager.checkMigration()
api = API()

//debugging layout
//let prs = PullRequest.allItemsOfType("PullRequest", inMoc: mainObjectContext) as [PullRequest]
//prs[0].condition = NSNumber(int: kPullRequestConditionMerged)
//prs[1].condition = NSNumber(int: kPullRequestConditionClosed)
//prs[2].condition = NSNumber(int: kPullRequestConditionMerged)
//prs[3].condition = NSNumber(int: kPullRequestConditionClosed)

#if os(iOS)
	UIApplicationMain(C_ARGC, C_ARGV, nil, NSStringFromClass(iOS_AppDelegate));
#else
	NSApplicationMain(C_ARGC, C_ARGV)
#endif
