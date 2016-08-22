
// OSX and iOS app init

Settings.checkMigration()
DataManager.checkMigration()
let api = API()


//debugging

//delay(2) {
//	let _items = PullRequest.allItems(ofType: "PullRequest", in: mainObjectContext) as! [ListableItem]
//	NotificationQueue.add(type: .newComment, forItem: _items[0].comments.first!)
//}
//let _items = PullRequest.allItems(ofType: "PullRequest", in: mainObjectContext) as! [ListableItem]
//for i in _items {
//	i.latestReadCommentDate = .distantPast
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
//	p.latestReadCommentDate = .distantPast
//	p.postProcess()
//}

/*
let testDate = "2016-02-01T08:58:18Z"

let d1 = syncDateFormatter.dateFromString(testDate)
let d2 = parseGH8601(testDate)
assert(d1==d2)

let s1 = Date()
for _ in 0...100000 {
	let dd1 = syncDateFormatter.dateFromString(testDate)
}
DLog("%@", Date().timeIntervalSinceDate(s1))

let s2 = Date()
for _ in 0...100000 {
	let dd1 = parseGH8601(testDate)
}
DLog("%@", Date().timeIntervalSinceDate(s2))
*/


#if os(iOS)
	import UIKit
	UIApplicationMain(
		CommandLine.argc,
		UnsafeMutablePointer<UnsafeMutablePointer<Int8>>(OpaquePointer(CommandLine.unsafeArgv)),
		nil,
		NSStringFromClass(iOS_AppDelegate.self))
#else
	_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
#endif
