
import CoreData
#if os(iOS)
	import UIKit
#endif

final class PRLabel: DataItem {

    @NSManaged var color: Int64
    @NSManaged var name: String?
    @NSManaged var url: String?

    @NSManaged var pullRequest: PullRequest?
	@NSManaged var issue: Issue?

	private class func labels(from data: [[AnyHashable : Any]]?, fromParent: ListableItem, postProcessCallback: (PRLabel, [AnyHashable : Any])->Void) {

		guard let infos=data, infos.count > 0 else { return }

		var namesOfItems = [String]()
		var namesToInfo = [String : [AnyHashable : Any]]()
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
				i.updatedAt = .distantPast
				i.createdAt = .distantPast
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

	class func syncLabels(from info: [[AnyHashable : Any]]?, withParent: ListableItem) {
		labels(from: info, fromParent: withParent) { label, info in
			label.url = info["url"] as? String
			if let c = info["color"] as? String {
				label.color = parse(from: c)
			} else {
				label.color = 0
			}
			label.postSyncAction = PostSyncAction.doNothing.rawValue
		}
	}

	private class func parse(from hex: String) -> Int64 {
		let safe = hex.trim.trimmingCharacters(in: CharacterSet.symbols)
		let s = Scanner(string: safe)
		var result: UInt32 = 0
		s.scanHexInt32(&result)
		return Int64(result)
	}

	var colorForDisplay: COLOR_CLASS {
		let c = UInt32(color)
		let red: UInt32 = (c & 0xFF0000)>>16
		let green: UInt32 = (c & 0x00FF00)>>8
		let blue: UInt32 = c & 0x0000FF
		let r = CGFloat(red)/255.0
		let g = CGFloat(green)/255.0
		let b = CGFloat(blue)/255.0
		return COLOR_CLASS(red: r, green: g, blue: b, alpha: 1.0)
	}
}
