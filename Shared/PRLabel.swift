
import CoreData
#if os(iOS)
	import UIKit
#endif

final class PRLabel: DataItem {

    @NSManaged var color: NSNumber?
    @NSManaged var name: String?
    @NSManaged var url: String?

    @NSManaged var pullRequest: PullRequest?
	@NSManaged var issue: Issue?

	class func labelWithName(name: String, withParent: DataItem) -> PRLabel? {
		let f = NSFetchRequest(entityName: "PRLabel")
		f.fetchLimit = 1
		f.returnsObjectsAsFaults = false
		if withParent is PullRequest {
			f.predicate = NSPredicate(format: "name == %@ and pullRequest == %@", name, withParent)
		} else {
			f.predicate = NSPredicate(format: "name == %@ and issue == %@", name, withParent)
		}
		let res = try! withParent.managedObjectContext?.executeFetchRequest(f) as! [PRLabel]
		return res.first
	}

	class func labelWithInfo(info: [NSObject : AnyObject], withParent: DataItem) -> PRLabel {
		let name = N(info, "name") as? String ?? "(unnamed label)"
		var l = PRLabel.labelWithName(name, withParent: withParent)
		if l==nil {
			DLog("Creating PRLabel: %@", name)
			l = NSEntityDescription.insertNewObjectForEntityForName("PRLabel", inManagedObjectContext: withParent.managedObjectContext!) as? PRLabel
			l!.name = name
			l!.serverId = 0
			l!.updatedAt = never()
			l!.createdAt = never()
			l!.apiServer = withParent.apiServer
			if let p = withParent as? PullRequest {
				l!.pullRequest = p
			} else if let i = withParent as? Issue {
				l!.issue = i
			}
		} else {
			DLog("Updating PRLabel: %@", name)
		}
		l!.url = N(info, "url") as? String
		if let c = N(info, "color") as? String {
			l!.color = NSNumber(unsignedInt: parseFromHex(c))
		} else {
			l!.color = 0
		}
		l!.postSyncAction = PostSyncAction.DoNothing.rawValue
		return l!
	}

	func colorForDisplay() -> COLOR_CLASS {
		if let c = color?.unsignedIntValue {
			return colorFromUInt32(c)
		} else {
			return COLOR_CLASS.blackColor()
		}
	}
}
