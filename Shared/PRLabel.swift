
import CoreData
#if os(iOS)
	import UIKit
#endif

@objc (PRLabel)
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
		let res = withParent.managedObjectContext?.executeFetchRequest(f, error: nil) as! [PRLabel]
		return res.first
	}

	class func labelWithInfo(info: NSDictionary, withParent: DataItem) -> PRLabel {
		let name = info.ofk("name") as? String ?? "(unnamed label)"
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
		l!.url = info.ofk("url") as? String
		if let c = info.ofk("color") as? String {
			l!.color = NSNumber(unsignedInt: c.parseFromHex())
		} else {
			l!.color = 0
		}
		l!.postSyncAction = PostSyncAction.DoNothing.rawValue
		return l!
	}

	func colorForDisplay() -> COLOR_CLASS {
		if let c = color?.unsignedLongLongValue {
			let red: UInt64 = (c & 0xFF0000)>>16
			let green: UInt64 = (c & 0x00FF00)>>8
			let blue: UInt64 = c & 0x0000FF
			let r = CGFloat(red)/255.0
			let g = CGFloat(green)/255.0
			let b = CGFloat(blue)/255.0
			return COLOR_CLASS(red: r, green: g, blue: b, alpha: 1.0)
		} else {
			return COLOR_CLASS.blackColor()
		}
	}
}
