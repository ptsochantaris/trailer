
import CoreData

@objc(DataItem)
class DataItem: NSManagedObject {

	@NSManaged var serverId: NSNumber?
	@NSManaged var postSyncAction: NSNumber?
	@NSManaged var createdAt: NSDate?
	@NSManaged var updatedAt: NSDate?
	@NSManaged var apiServer: ApiServer

	class func allItemsOfType(type: String, inMoc: NSManagedObjectContext) -> [DataItem] {
		let f = NSFetchRequest(entityName: type)
		f.returnsObjectsAsFaults = false
		return inMoc.executeFetchRequest(f, error: nil) as [DataItem]
	}

	class func allItemsOfType(type: String, fromServer: ApiServer) -> [DataItem] {
		let f = NSFetchRequest(entityName: type)
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "apiServer == %@", fromServer)
		return fromServer.managedObjectContext?.executeFetchRequest(f, error: nil) as [DataItem]
	}

	class func itemOfType(type: String, serverId: NSNumber, fromServer: ApiServer) -> DataItem? {
		let f = NSFetchRequest(entityName: type)
		f.returnsObjectsAsFaults = false
		f.fetchLimit = 1
		f.predicate = NSPredicate(format:"serverId = %@ and apiServer == %@", serverId, fromServer)
		let items = fromServer.managedObjectContext?.executeFetchRequest(f, error: nil)
		return items?.first as? DataItem
	}

	class func itemWithInfo(info: NSDictionary, type: String, fromServer: ApiServer) -> DataItem {
		let serverId = info.ofk("id") as NSNumber
		let updatedDate = syncDateFormatter.dateFromString(info.ofk("updated_at") as String)
		var existingItem = itemOfType(type, serverId: serverId, fromServer: fromServer)
		if existingItem == nil {
			DLog("Creating %@: %@",type,serverId)
			existingItem = NSEntityDescription.insertNewObjectForEntityForName(type, inManagedObjectContext: fromServer.managedObjectContext!) as? DataItem
			existingItem!.serverId = serverId
			existingItem!.createdAt = syncDateFormatter.dateFromString(info.ofk("created_at") as String)
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

	class func itemsOfType(type: String, surviving: Bool, inMoc: NSManagedObjectContext) -> [DataItem] {
		let f = NSFetchRequest(entityName: type)
		if surviving {
			f.returnsObjectsAsFaults = false
			f.predicate = NSPredicate(format: "postSyncAction != %d", PostSyncAction.Delete.rawValue)
		} else {
			f.returnsObjectsAsFaults = true
			f.predicate = NSPredicate(format: "postSyncAction = %d", PostSyncAction.Delete.rawValue)
		}
		return inMoc.executeFetchRequest(f, error: nil) as [DataItem]
	}

	class func newOrUpdatedItemsOfType(type: String, inMoc: NSManagedObjectContext) -> [DataItem] {
		let f = NSFetchRequest(entityName: type)
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "postSyncAction = %d or postSyncAction = %d", PostSyncAction.NoteNew.rawValue, PostSyncAction.NoteUpdated.rawValue)
		return inMoc.executeFetchRequest(f, error: nil) as [DataItem]
	}

	class func updatedItemsOfType(type: String, inMoc: NSManagedObjectContext) -> [DataItem] {
		let f = NSFetchRequest(entityName: type)
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "postSyncAction = %d", PostSyncAction.NoteUpdated.rawValue)
		return inMoc.executeFetchRequest(f, error: nil) as [DataItem]
	}

	class func newItemsOfType(type: String, inMoc: NSManagedObjectContext) -> [DataItem] {
		let f = NSFetchRequest(entityName: type)
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "postSyncAction = %d", PostSyncAction.NoteNew.rawValue)
		return inMoc.executeFetchRequest(f, error: nil) as [DataItem]
	}

	class func nukeDeletedItemsInMoc(moc: NSManagedObjectContext) {
		let types = ["Repo", "PullRequest", "PRStatus", "PRComment", "PRLabel"]
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

	class func countItemsOfType(type: String, moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest(entityName: type)
		return moc.countForFetchRequest(f, error: nil)
	}

	/*
	override func prepareForDeletion() {
		DLog("Deleting %@ ID: %@", entity.name, serverId)
		super.prepareForDeletion()
	}
	*/
}
