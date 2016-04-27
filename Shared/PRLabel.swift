
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

	private class func labelsWithInfo(data: [[NSObject : AnyObject]]?, fromParent: ListableItem, postProcessCallback: (PRLabel, [NSObject : AnyObject])->Void) {

		if data==nil { return }

		var namesOfItems = [String]()
		var namesToInfo = [String : [NSObject : AnyObject]]()
		for info in data ?? [] {
			let name = info["name"] as? String ?? ""
			namesOfItems.append(name)
			namesToInfo[name] = info
		}

		let f = NSFetchRequest(entityName: "PRLabel")
		f.returnsObjectsAsFaults = false
		if fromParent is PullRequest {
			f.predicate = NSPredicate(format:"name in %@ and pullRequest == %@", namesOfItems, fromParent)
		} else {
			f.predicate = NSPredicate(format:"name in %@ and issue == %@", namesOfItems, fromParent)
		}
		let existingItems = try! fromParent.managedObjectContext?.executeFetchRequest(f) as? [PRLabel] ?? []

		for i in existingItems {
			let name = i.name!
			namesOfItems.removeAtIndex(namesOfItems.indexOf(name)!)
			let info = namesToInfo[name]!
			DLog("Updating Label: %@", name)
			postProcessCallback(i, info)
		}

		for name in namesOfItems {
			DLog("Creating Label: %@", name)
			let info = namesToInfo[name]!
			let i = NSEntityDescription.insertNewObjectForEntityForName("PRLabel", inManagedObjectContext: fromParent.managedObjectContext!) as! PRLabel
			i.name = name
			i.serverId = 0
			i.updatedAt = never()
			i.createdAt = never()
			i.apiServer = fromParent.apiServer
			if let pr = fromParent as? PullRequest {
				i.pullRequest = pr
			} else if let issue = fromParent as? Issue {
				i.issue = issue
			}
			postProcessCallback(i, info)
		}
	}

	class func syncLabelsWithInfo(info: [[NSObject : AnyObject]]?, withParent: ListableItem) {
		labelsWithInfo(info, fromParent: withParent) { label, info in
			label.url = info["url"] as? String
			if let c = info["color"] as? String {
				label.color = NSNumber(unsignedInt: parseFromHex(c))
			} else {
				label.color = 0
			}
			label.postSyncAction = PostSyncAction.DoNothing.rawValue
		}
	}

	var colorForDisplay: COLOR_CLASS {
		if let c = color {
			return colorFromUInt32(c.unsignedIntValue)
		} else {
			return COLOR_CLASS.blackColor()
		}
	}
}
