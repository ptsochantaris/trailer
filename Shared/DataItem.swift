
import CoreData

class DataItem: NSManagedObject {

	@NSManaged var serverId: NSNumber?
	@NSManaged var postSyncAction: NSNumber?
	@NSManaged var createdAt: Date?
	@NSManaged var updatedAt: Date?
	@NSManaged var apiServer: ApiServer

	func resetSyncState() {
		updatedAt = Date.distantPast
		apiServer.resetSyncState()
	}

	final class func allItemsOfType(_ type: String, inMoc: NSManagedObjectContext) -> [DataItem] {
		let f = NSFetchRequest<DataItem>(entityName: type)
		f.returnsObjectsAsFaults = false
		return try! inMoc.fetch(f)
	}

	final class func allItemsOfType(_ type: String, fromServer: ApiServer) -> [DataItem] {
		let f = NSFetchRequest<DataItem>(entityName: type)
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "apiServer == %@", fromServer)
		return try! fromServer.managedObjectContext!.fetch(f)
	}

	final class func itemOfType(_ type: String, serverId: NSNumber, fromServer: ApiServer) -> DataItem? {
		let f = NSFetchRequest<DataItem>(entityName: type)
		f.returnsObjectsAsFaults = false
		f.fetchLimit = 1
		f.predicate = NSPredicate(format:"serverId = %@ and apiServer == %@", serverId, fromServer)
		let items = try! fromServer.managedObjectContext!.fetch(f)
		return items.first
	}

	final class func itemsWithInfo(_ data: [[NSObject : AnyObject]]?, type: String, fromServer: ApiServer, postProcessCallback: (DataItem, [NSObject : AnyObject], Bool)->Void) {

		guard let infos=data, infos.count > 0 else { return }

		var idsOfItems = [NSNumber]()
		var idsToInfo = [NSNumber : [NSObject : AnyObject]]()
		for info in infos {
			if let serverId = info["id"] as? NSNumber {
				idsOfItems.append(serverId)
				idsToInfo[serverId] = info
			}
		}

		if idsOfItems.count == 0 { return }

		let f = NSFetchRequest<DataItem>(entityName: type)
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format:"serverId in %@ and apiServer == %@", idsOfItems, fromServer)
		let existingItems = try! fromServer.managedObjectContext?.fetch(f) ?? []

		for i in existingItems {
			if let serverId = i.serverId, let idx = idsOfItems.index(of: serverId), let info = idsToInfo[serverId] {
				idsOfItems.remove(at: idx)
				let updatedDate = parseGH8601(info["updated_at"] as? String) ?? Date()
				if updatedDate != i.updatedAt {
					DLog("Updating %@: %@",type,serverId)
					i.postSyncAction = PostSyncAction.noteUpdated.rawValue
					i.updatedAt = updatedDate
					postProcessCallback(i, info, true)
				} else {
					//DLog("Skipping %@: %@",type,serverId)
					i.postSyncAction = PostSyncAction.doNothing.rawValue
					postProcessCallback(i, info, false)
				}
			}
		}

		for serverId in idsOfItems {
			if let info = idsToInfo[serverId] {
				DLog("Creating %@: %@", type, serverId)
				let i = NSEntityDescription.insertNewObject(forEntityName: type, into: fromServer.managedObjectContext!) as! DataItem
				i.serverId = serverId
				i.postSyncAction = PostSyncAction.noteNew.rawValue
				i.apiServer = fromServer

				i.createdAt = parseGH8601(info["created_at"] as? String) ?? Date()
				i.updatedAt = parseGH8601(info["updated_at"] as? String) ?? Date()

				postProcessCallback(i, info, true)
			}
		}
	}

	final class func itemsOfType(_ type: String, surviving: Bool, inMoc: NSManagedObjectContext) -> [DataItem] {
		let f = NSFetchRequest<DataItem>(entityName: type)
		if surviving {
			f.returnsObjectsAsFaults = false
			f.predicate = NSPredicate(format: "postSyncAction != %d", PostSyncAction.delete.rawValue)
		} else {
			f.returnsObjectsAsFaults = true
			f.predicate = NSPredicate(format: "postSyncAction = %d", PostSyncAction.delete.rawValue)
		}
		return try! inMoc.fetch(f)
	}

	final class func newOrUpdatedItemsOfType(_ type: String, inMoc: NSManagedObjectContext) -> [DataItem] {
		let f = NSFetchRequest<DataItem>(entityName: type)
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "postSyncAction = %d or postSyncAction = %d", PostSyncAction.noteNew.rawValue, PostSyncAction.noteUpdated.rawValue)
		return try! inMoc.fetch(f)
	}

	final class func updatedItemsOfType(_ type: String, inMoc: NSManagedObjectContext) -> [DataItem] {
		let f = NSFetchRequest<DataItem>(entityName: type)
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "postSyncAction = %d", PostSyncAction.noteUpdated.rawValue)
		return try! inMoc.fetch(f)
	}

	final class func newItemsOfType(_ type: String, inMoc: NSManagedObjectContext) -> [DataItem] {
		let f = NSFetchRequest<DataItem>(entityName: type)
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "postSyncAction = %d", PostSyncAction.noteNew.rawValue)
		return try! inMoc.fetch(f)
	}

	final class func nukeDeletedItemsInMoc(_ moc: NSManagedObjectContext) {
		let types = ["Repo", "PullRequest", "PRStatus", "PRComment", "PRLabel", "Issue", "Team"]
		var count = 0
		for type in types {
			let discarded = itemsOfType(type, surviving: false, inMoc: moc)
			if discarded.count > 0 {
				count += discarded.count
				DLog("Nuking %d %@ items marked for deletion", discarded.count, type)
				for i in discarded {
					moc.delete(i)
				}
			}
		}
		DLog("Nuked total %d items marked for deletion", count)
	}

	final class func countItemsOfType(_ type: String, moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest<DataItem>(entityName: type)
		return try! moc.count(for: f)
	}

	class func addCriterion<T: ListableItem>(_ criterion: GroupingCriterion?, toFetchRequest: NSFetchRequest<T>, originalPredicate: NSPredicate, inMoc: NSManagedObjectContext, includeAllGroups: Bool = false) {
		var andPredicates = [NSPredicate]()
		if let c = criterion {
			andPredicates.append(c.addCriterionToPredicate(originalPredicate, inMoc: inMoc))
		} else {
			andPredicates.append(originalPredicate)
		}
		if !includeAllGroups && criterion?.repoGroup == nil {
			for otherGroup in Repo.allGroupLabels {
				let p = NSPredicate(format: "repo.groupLabel == nil or repo.groupLabel != %@", otherGroup)
				andPredicates.append(p)
			}
		}
		if andPredicates.count == 1 {
			toFetchRequest.predicate = andPredicates.first
		} else {
			toFetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: andPredicates)
		}
	}
}
