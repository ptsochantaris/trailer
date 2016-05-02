
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
//_prs[0].condition = ItemCondition.Merged.rawValue
//_prs[1].condition = ItemCondition.Closed.rawValue
//for p in _prs {
//	p.latestReadCommentDate = never()
//	p.postProcess()
//}

/*
let testDate = "2016-02-01T08:58:18Z"

let d1 = syncDateFormatter.dateFromString(testDate)
let d2 = parseGH8601(testDate)
assert(d1==d2)

let s1 = NSDate()
for _ in 0...100000 {
	let dd1 = syncDateFormatter.dateFromString(testDate)
}
DLog("%f", NSDate().timeIntervalSinceDate(s1))

let s2 = NSDate()
for _ in 0...100000 {
	let dd1 = parseGH8601(testDate)
}
DLog("%f", NSDate().timeIntervalSinceDate(s2))
*/


#if os(iOS)
	import UIKit
	UIApplicationMain(Process.argc, Process.unsafeArgv, nil, NSStringFromClass(iOS_AppDelegate))
#else
	NSApplicationMain(Process.argc, Process.unsafeArgv)
#endif
