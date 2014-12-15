
kPullRequestSectionNames = ["", "Mine", "Participated", "Recently Merged", "Recently Closed", "All Pull Requests"]
currentAppVersion = NSBundle.mainBundle().infoDictionary!["CFBundleShortVersionString"] as String
DataManager.checkMigration()
api = API()

//debugging sections
//let _prs = PullRequest.allItemsOfType("PullRequest", inMoc: mainObjectContext) as [PullRequest]
//let _apis = ApiServer.allApiServersInMoc(mainObjectContext)
//prs[0].condition = NSNumber(integer: PullRequestCondition.Merged.rawValue)
//prs[1].condition = NSNumber(integer: PullRequestCondition.Closed.rawValue)
//prs[2].condition = NSNumber(integer: PullRequestCondition.Merged.rawValue)
//prs[3].condition = NSNumber(integer: PullRequestCondition.Closed.rawValue)

/*
let dataTest = NSString(contentsOfFile: "/Users/ptsochantaris/Desktop/json.txt", encoding: NSUTF8StringEncoding, error: nil)!
let ddTest = dataTest.dataUsingEncoding(NSUTF8StringEncoding)!
var ddd:AnyObject = NSJSONSerialization.JSONObjectWithData(ddTest, options:NSJSONReadingOptions.allZeros, error:nil)!

for i in (ddd as [NSDictionary]) {
	let s = PRStatus.statusWithInfo(i, fromServer: _apis[0])
	s.pullRequest = _prs[0]
}
*/

#if os(iOS)
	UIApplicationMain(C_ARGC, C_ARGV, nil, NSStringFromClass(iOS_AppDelegate));
#else
	NSApplicationMain(C_ARGC, C_ARGV)
#endif
