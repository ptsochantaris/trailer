
import CoreData

class DataItem: NSManagedObject {

	@NSManaged var serverId: NSNumber?
	@NSManaged var postSyncAction: NSNumber?
	@NSManaged var createdAt: NSDate?
	@NSManaged var updatedAt: NSDate?
	@NSManaged var apiServer: ApiServer

	func resetSyncState() {
		updatedAt = never()
		apiServer.resetSyncState()
	}

	final class func allItemsOfType(type: String, inMoc: NSManagedObjectContext) -> [DataItem] {
		let f = NSFetchRequest(entityName: type)
		f.returnsObjectsAsFaults = false
		return try! inMoc.executeFetchRequest(f) as! [DataItem]
	}

	final class func allItemsOfType(type: String, fromServer: ApiServer) -> [DataItem] {
		let f = NSFetchRequest(entityName: type)
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "apiServer == %@", fromServer)
		return try! fromServer.managedObjectContext?.executeFetchRequest(f) as! [DataItem]
	}

	final class func itemOfType(type: String, serverId: NSNumber, fromServer: ApiServer) -> DataItem? {
		let f = NSFetchRequest(entityName: type)
		f.returnsObjectsAsFaults = false
		f.fetchLimit = 1
		f.predicate = NSPredicate(format:"serverId = %@ and apiServer == %@", serverId, fromServer)
		let items: [AnyObject]?
		do {
			items = try fromServer.managedObjectContext?.executeFetchRequest(f)
		} catch _ {
			items = nil
		}
		return items?.first as? DataItem
	}

	final class func itemsWithInfo(data: [[NSObject : AnyObject]]?, type: String, fromServer: ApiServer, postProcessCallback: (DataItem, [NSObject : AnyObject], Bool)->Void) {

		if data==nil { return }

		var idsOfItems = [NSNumber]()
		var idsToInfo = [NSNumber : [NSObject : AnyObject]]()
		for info in data ?? [] {
			let serverId = info["id"] as! NSNumber
			idsOfItems.append(serverId)
			idsToInfo[serverId] = info
		}

		let f = NSFetchRequest(entityName: type)
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format:"serverId in %@ and apiServer == %@", idsOfItems, fromServer)
		let existingItems = try! fromServer.managedObjectContext?.executeFetchRequest(f) as? [DataItem] ?? []

		for i in existingItems {
			let serverId = i.serverId!
			idsOfItems.removeAtIndex(idsOfItems.indexOf(serverId)!)
			let info = idsToInfo[serverId]!
			let updatedDate = parseGH8601(info["updated_at"] as? String) ?? NSDate()
			if updatedDate != i.updatedAt {
				DLog("Updating %@: %@",type,serverId)
				i.postSyncAction = PostSyncAction.NoteUpdated.rawValue
				i.updatedAt = updatedDate
				postProcessCallback(i, info, true)
			} else {
				//DLog("Skipping %@: %@",type,serverId)
				i.postSyncAction = PostSyncAction.DoNothing.rawValue
				postProcessCallback(i, info, false)
			}
		}

		for serverId in idsOfItems {
			DLog("Creating %@: %@", type, serverId)
			let info = idsToInfo[serverId]!
			let i = NSEntityDescription.insertNewObjectForEntityForName(type, inManagedObjectContext: fromServer.managedObjectContext!) as! DataItem
			i.serverId = serverId
			i.postSyncAction = PostSyncAction.NoteNew.rawValue
			i.apiServer = fromServer

			i.createdAt = parseGH8601(info["created_at"] as? String) ?? NSDate()
			i.updatedAt = parseGH8601(info["updated_at"] as? String) ?? NSDate()

			postProcessCallback(i, info, true)
		}
	}

	final class func itemsOfType(type: String, surviving: Bool, inMoc: NSManagedObjectContext) -> [DataItem] {
		let f = NSFetchRequest(entityName: type)
		if surviving {
			f.returnsObjectsAsFaults = false
			f.predicate = NSPredicate(format: "postSyncAction != %d", PostSyncAction.Delete.rawValue)
		} else {
			f.returnsObjectsAsFaults = true
			f.predicate = NSPredicate(format: "postSyncAction = %d", PostSyncAction.Delete.rawValue)
		}
		return try! inMoc.executeFetchRequest(f) as! [DataItem]
	}

	final class func newOrUpdatedItemsOfType(type: String, inMoc: NSManagedObjectContext) -> [DataItem] {
		let f = NSFetchRequest(entityName: type)
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "postSyncAction = %d or postSyncAction = %d", PostSyncAction.NoteNew.rawValue, PostSyncAction.NoteUpdated.rawValue)
		return try! inMoc.executeFetchRequest(f) as! [DataItem]
	}

	final class func updatedItemsOfType(type: String, inMoc: NSManagedObjectContext) -> [DataItem] {
		let f = NSFetchRequest(entityName: type)
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "postSyncAction = %d", PostSyncAction.NoteUpdated.rawValue)
		return try! inMoc.executeFetchRequest(f) as! [DataItem]
	}

	final class func newItemsOfType(type: String, inMoc: NSManagedObjectContext) -> [DataItem] {
		let f = NSFetchRequest(entityName: type)
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "postSyncAction = %d", PostSyncAction.NoteNew.rawValue)
		return try! inMoc.executeFetchRequest(f) as! [DataItem]
	}

	final class func nukeDeletedItemsInMoc(moc: NSManagedObjectContext) {
		let types = ["Repo", "PullRequest", "PRStatus", "PRComment", "PRLabel", "Issue", "Team"]
		var count = 0
		for type in types {
			let discarded = itemsOfType(type, surviving: false, inMoc: moc)
			if discarded.count > 0 {
				count += discarded.count
				DLog("Nuking %d %@ items marked for deletion", discarded.count, type)
				for i in discarded {
					moc.deleteObject(i)
				}
			}
		}
		DLog("Nuked total %d items marked for deletion", count)
	}

	final class func countItemsOfType(type: String, moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest(entityName: type)
		return moc.countForFetchRequest(f, error: nil)
	}
}
