
import CoreData

class DataItem: NSManagedObject {

	@NSManaged var serverId: Int64
	@NSManaged var postSyncAction: Int64
	@NSManaged var createdAt: Date?
	@NSManaged var updatedAt: Date?
	@NSManaged var apiServer: ApiServer

	func resetSyncState() {
		updatedAt = Date.distantPast
		apiServer.resetSyncState()
	}

	final class func allItems(ofType type: String, in moc: NSManagedObjectContext) -> [DataItem] {
		let f = NSFetchRequest<DataItem>(entityName: type)
		f.returnsObjectsAsFaults = false
		return try! moc.fetch(f)
	}

	final class func allItems(ofType type: String, server: ApiServer) -> [DataItem] {
		let f = NSFetchRequest<DataItem>(entityName: type)
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "apiServer == %@", server)
		return try! server.managedObjectContext!.fetch(f)
	}

	final class func items(with data: [[NSObject : AnyObject]]?, type: String, server: ApiServer, postProcessCallback: (DataItem, [NSObject : AnyObject], Bool)->Void) {

		guard let infos=data, infos.count > 0 else { return }

		var idsOfItems = [Int64]()
		var idsToInfo = [Int64 : [NSObject : AnyObject]]()
		for info in infos {
			if let serverId = info["id"] as? NSNumber {
				let sid = serverId.int64Value
				idsOfItems.append(sid)
				idsToInfo[sid] = info
			}
		}

		if idsOfItems.count == 0 { return }

		let f = NSFetchRequest<DataItem>(entityName: type)
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format:"serverId in %@ and apiServer == %@", idsOfItems.map { NSNumber(value: $0) }, server)
		let existingItems = try! server.managedObjectContext?.fetch(f) ?? []

		for i in existingItems {
			let serverId = i.serverId
			if let idx = idsOfItems.index(of: serverId), let info = idsToInfo[serverId] {
				idsOfItems.remove(at: idx)
				let updatedDate = parseGH8601(info["updated_at"] as? String) ?? Date()
				if updatedDate != i.updatedAt {
					DLog("Updating %@: %lld", type, serverId)
					i.postSyncAction = PostSyncAction.noteUpdated.rawValue
					i.updatedAt = updatedDate
					postProcessCallback(i, info, true)
				} else {
					//DLog("Skipping %@: %lld",type,serverId)
					i.postSyncAction = PostSyncAction.doNothing.rawValue
					postProcessCallback(i, info, false)
				}
			}
		}

		for serverId in idsOfItems {
			if let info = idsToInfo[serverId] {
				DLog("Creating %@: %lld", type, serverId)
				let i = NSEntityDescription.insertNewObject(forEntityName: type, into: server.managedObjectContext!) as! DataItem
				i.serverId = serverId
				i.postSyncAction = PostSyncAction.noteNew.rawValue
				i.apiServer = server

				i.createdAt = parseGH8601(info["created_at"] as? String) ?? Date()
				i.updatedAt = parseGH8601(info["updated_at"] as? String) ?? Date()

				postProcessCallback(i, info, true)
			}
		}
	}

	final class func items(ofType type: String, surviving: Bool, in moc: NSManagedObjectContext) -> [DataItem] {
		let f = NSFetchRequest<DataItem>(entityName: type)
		if surviving {
			f.returnsObjectsAsFaults = false
			f.predicate = NSPredicate(format: "postSyncAction != %lld", PostSyncAction.delete.rawValue)
		} else {
			f.returnsObjectsAsFaults = true
			f.predicate = NSPredicate(format: "postSyncAction = %lld", PostSyncAction.delete.rawValue)
		}
		return try! moc.fetch(f)
	}

	final class func newOrUpdatedItems(ofType type: String, in moc: NSManagedObjectContext) -> [DataItem] {
		let f = NSFetchRequest<DataItem>(entityName: type)
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "postSyncAction = %lld or postSyncAction = %lld", PostSyncAction.noteNew.rawValue, PostSyncAction.noteUpdated.rawValue)
		return try! moc.fetch(f)
	}

	final class func updatedItems(ofType type: String, in moc: NSManagedObjectContext) -> [DataItem] {
		let f = NSFetchRequest<DataItem>(entityName: type)
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "postSyncAction = %lld", PostSyncAction.noteUpdated.rawValue)
		return try! moc.fetch(f)
	}

	final class func newItems(ofType type: String, in moc: NSManagedObjectContext) -> [DataItem] {
		let f = NSFetchRequest<DataItem>(entityName: type)
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "postSyncAction = %lld", PostSyncAction.noteNew.rawValue)
		return try! moc.fetch(f)
	}

	final class func nukeDeletedItems(in moc: NSManagedObjectContext) {
		let types = ["Repo", "PullRequest", "PRStatus", "PRComment", "PRLabel", "Issue", "Team"]
		var count = 0
		for type in types {
			let discarded = items(ofType: type, surviving: false, in: moc)
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

	final class func countItems(ofType type: String, in moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest<DataItem>(entityName: type)
		return try! moc.count(for: f)
	}

	class func add<T: ListableItem>(criterion: GroupingCriterion?, toFetchRequest: NSFetchRequest<T>, originalPredicate: NSPredicate, in moc: NSManagedObjectContext, includeAllGroups: Bool = false) {
		var andPredicates = [NSPredicate]()
		if let c = criterion {
			andPredicates.append(c.addCriterion(to: originalPredicate, in: moc))
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
