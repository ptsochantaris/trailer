
Settings.checkMigration()
DataManager.checkMigration()
let api = API()


//debugging sections
//let _apis = ApiServer.allApiServersInMoc(mainObjectContext)
//_prs[0].condition = NSNumber(integer: PullRequestCondition.Merged.rawValue)
//_prs[1].condition = NSNumber(integer: PullRequestCondition.Closed.rawValue)
//_prs[2].condition = NSNumber(integer: PullRequestCondition.Merged.rawValue)
//_prs[3].condition = NSNumber(integer: PullRequestCondition.Closed.rawValue)

/*let _prs = PullRequest.allItemsOfType("PullRequest", inMoc: mainObjectContext) as! [PullRequest]
for p in _prs {
    for c in p.comments.allObjects as! [PRComment] {
        mainObjectContext.deleteObject(c)
    }
	p.latestReadCommentDate = nil
	p.updatedAt = NSDate.distantPast() as? NSDate
	p.repo.dirty = true
	p.repo.updatedAt = NSDate.distantPast() as? NSDate
}
DataManager.saveDB()
*/

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
	import UIKit
	UIApplicationMain(Process.argc, Process.unsafeArgv, nil, NSStringFromClass(iOS_AppDelegate))
#else
	NSApplicationMain(Process.argc, Process.unsafeArgv)
#endif
