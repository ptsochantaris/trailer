
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

	final class func itemWithInfo(info: [NSObject : AnyObject], type: String, fromServer: ApiServer) -> DataItem {
		let serverId = N(info, "id") as! NSNumber
		let updatedDate = syncDateFormatter.dateFromString(N(info, "updated_at") as! String)
		var existingItem = itemOfType(type, serverId: serverId, fromServer: fromServer)
		if existingItem == nil {
			DLog("Creating %@: %@",type,serverId)
			existingItem = NSEntityDescription.insertNewObjectForEntityForName(type, inManagedObjectContext: fromServer.managedObjectContext!) as? DataItem
			existingItem!.serverId = serverId
			existingItem!.createdAt = syncDateFormatter.dateFromString(N(info, "created_at") as! String)
			existingItem!.postSyncAction = PostSyncAction.NoteNew.rawValue
			existingItem!.updatedAt = updatedDate
			existingItem!.apiServer = fromServer
		} else if updatedDate != existingItem!.updatedAt {
			DLog("Updating %@: %@",type,serverId)
			existingItem!.postSyncAction = PostSyncAction.NoteUpdated.rawValue
			existingItem!.updatedAt = updatedDate
		} else {
			DLog("Skipping %@: %@",type,serverId)
			existingItem!.postSyncAction = PostSyncAction.DoNothing.rawValue
		}
		return existingItem!
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
