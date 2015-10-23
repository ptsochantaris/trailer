
// OSX and iOS app init

Settings.checkMigration()
DataManager.checkMigration()
let api = API()


//debugging
/*
let _prs = PullRequest.activePullRequestsInMoc(mainObjectContext, visibleOnly: true)
//_prs[0].condition = PullRequestCondition.Merged.rawValue
//_prs[1].condition = PullRequestCondition.Closed.rawValue
for p in _prs {
	p.latestReadCommentDate = never()
	p.postProcess()
}
*/


#if os(iOS)
	import UIKit
	UIApplicationMain(Process.argc, Process.unsafeArgv, nil, NSStringFromClass(iOS_AppDelegate))
#else
	NSApplicationMain(Process.argc, Process.unsafeArgv)
#endif
