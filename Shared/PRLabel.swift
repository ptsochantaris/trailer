
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

	private class func labelsWithInfo(_ data: [[NSObject : AnyObject]]?, fromParent: ListableItem, postProcessCallback: (PRLabel, [NSObject : AnyObject])->Void) {

		guard let infos=data, infos.count > 0 else { return }

		var namesOfItems = [String]()
		var namesToInfo = [String : [NSObject : AnyObject]]()
		for info in infos {
			if let name = info["name"] as? String {
				namesOfItems.append(name)
				namesToInfo[name] = info
			}
		}

		if namesOfItems.count == 0 { return }

		let f = NSFetchRequest<PRLabel>(entityName: "PRLabel")
		f.returnsObjectsAsFaults = false
		if fromParent is PullRequest {
			f.predicate = NSPredicate(format:"name in %@ and pullRequest == %@", namesOfItems, fromParent)
		} else {
			f.predicate = NSPredicate(format:"name in %@ and issue == %@", namesOfItems, fromParent)
		}
		let existingItems = try! fromParent.managedObjectContext?.fetch(f) ?? []

		for i in existingItems {
			if let name = i.name, let idx = namesOfItems.index(of: name), let info = namesToInfo[name] {
				namesOfItems.remove(at: idx)
				DLog("Updating Label: %@", name)
				postProcessCallback(i, info)
			}
		}

		for name in namesOfItems {
			if let info = namesToInfo[name] {
				DLog("Creating Label: %@", name)
				let i = NSEntityDescription.insertNewObject(forEntityName: "PRLabel", into: fromParent.managedObjectContext!) as! PRLabel
				i.name = name
				i.serverId = 0
				i.updatedAt = Date.distantPast
				i.createdAt = Date.distantPast
				i.apiServer = fromParent.apiServer
				if let pr = fromParent as? PullRequest {
					i.pullRequest = pr
				} else if let issue = fromParent as? Issue {
					i.issue = issue
				}
				postProcessCallback(i, info)
			}
		}
	}

	class func syncLabelsWithInfo(_ info: [[NSObject : AnyObject]]?, withParent: ListableItem) {
		labelsWithInfo(info, fromParent: withParent) { label, info in
			label.url = info["url"] as? String
			if let c = info["color"] as? String {
				label.color = NSNumber(value: parseFromHex(c))
			} else {
				label.color = 0
			}
			label.postSyncAction = PostSyncAction.doNothing.rawValue
		}
	}

	var colorForDisplay: COLOR_CLASS {
		if let c = color {
			return colorFromUInt32(c.uint32Value)
		} else {
			return COLOR_CLASS.black
		}
	}
}
