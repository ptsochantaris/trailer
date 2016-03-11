
// OSX and iOS app init

Settings.checkMigration()
DataManager.checkMigration()
let api = API()


//debugging
//let _items = PullRequest.allItemsOfType("PullRequest", inMoc: mainObjectContext) as! [ListableItem]
//for i in _items {
//	i.latestReadCommentDate = never()
//	for c in i.comments {
//		mainObjectContext.deleteObject(c)
//	}
//	i.postProcess()
//}
//for s in _prs[0].statuses {
//	s.state = "failed"
//}
//_prs[0].condition = PullRequestCondition.Merged.rawValue
//_prs[1].condition = PullRequestCondition.Closed.rawValue
//for p in _prs {
//	p.latestReadCommentDate = never()
//	p.postProcess()
//}


#if os(iOS)
	import UIKit
	UIApplicationMain(Process.argc, Process.unsafeArgv, nil, NSStringFromClass(iOS_AppDelegate))
#else
	NSApplicationMain(Process.argc, Process.unsafeArgv)
#endif
