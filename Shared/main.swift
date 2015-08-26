
// OSX and iOS app init

Settings.checkMigration()
DataManager.checkMigration()
let api = API()


//debugging sections
//let _apis = ApiServer.allApiServersInMoc(mainObjectContext
//_prs[0].condition = PullRequestCondition.Merged.rawValue
//_prs[1].condition = PullRequestCondition.Closed.rawValue
//_prs[2].condition = PullRequestCondition.Merged.rawValue
//_prs[3].condition = PullRequestCondition.Closed.rawValue
/*
let _prs = DataItem.allItemsOfType("PullRequest", inMoc: mainObjectContext) as! [PullRequest]
for p in _prs {
	p.latestReadCommentDate = never()
}
let _issues = DataItem.allItemsOfType("Issue", inMoc: mainObjectContext) as! [Issue]
for p in _issues {
	p.latestReadCommentDate = never()
}
DataManager.saveDB()
*/

#if os(iOS)
	import UIKit
	UIApplicationMain(Process.argc, Process.unsafeArgv, nil, NSStringFromClass(iOS_AppDelegate))
#else
	NSApplicationMain(Process.argc, Process.unsafeArgv)
#endif
