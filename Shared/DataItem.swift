
import CoreData

class DataItem: NSManagedObject {

	@NSManaged var serverId: Int64
	@NSManaged var postSyncAction: Int64
	@NSManaged var createdAt: Date?
	@NSManaged var updatedAt: Date?
	@NSManaged var apiServer: ApiServer

	func resetSyncState() {
		updatedAt = updatedAt?.addingTimeInterval(-1) ?? .distantPast
		apiServer.resetSyncState()
	}

	final func createdBefore(_ item: DataItem) -> Bool {
		return (createdAt ?? .distantPast) < (item.createdAt ?? .distantPast) || serverId < item.serverId
	}

	static func allItems<T: DataItem>(of type: T.Type, in moc: NSManagedObjectContext, prefetchRelationships: [String]? = nil) -> [T] {
		let f = NSFetchRequest<T>(entityName: String(describing: type))
		f.relationshipKeyPathsForPrefetching = prefetchRelationships
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		return try! moc.fetch(f)
	}

	static func allItems<T: DataItem>(of type: T.Type, in server: ApiServer) -> [T] {
		let f = NSFetchRequest<T>(entityName: String(describing: type))
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "apiServer == %@", server)
		return try! server.managedObjectContext!.fetch(f)
	}

	static func items<T: DataItem>(with data: [[AnyHashable : Any]]?,
	                       type: T.Type,
	                       server: ApiServer,
	                       prefetchRelationships: [String]? = nil,
	                       createNewItems: Bool = true,
	                       postProcessCallback: (T, [AnyHashable : Any], Bool) -> Void) {

		guard let infos = data, infos.count > 0 else { return }

		var idsOfItems = [Int64]()
		idsOfItems.reserveCapacity(infos.count)
		var idsToInfo = [Int64 : [AnyHashable : Any]]()
		for info in infos {
			if let serverId = info["id"] as? Int64 {
				idsOfItems.append(serverId)
				idsToInfo[serverId] = info
			}
		}

		if idsOfItems.count == 0 { return }

		let entityName = String(describing: type)
		let f = NSFetchRequest<T>(entityName: entityName)
		f.relationshipKeyPathsForPrefetching = prefetchRelationships
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		f.predicate = NSPredicate(format:"serverId in %@ and apiServer == %@", idsOfItems, server)
		let existingItems = try! server.managedObjectContext?.fetch(f) ?? []

		let now = Date()

		for i in existingItems {
			let serverId = i.serverId
			if let idx = idsOfItems.firstIndex(of: serverId), let info = idsToInfo[serverId] {
				idsOfItems.remove(at: idx)
				let updatedDate = DataItem.parseGH8601(info["updated_at"] as? String) ?? i.createdAt ?? now
				if updatedDate != i.updatedAt {
					DLog("Updating %@: %@", entityName, serverId)
					i.postSyncAction = PostSyncAction.isUpdated.rawValue
					i.updatedAt = updatedDate
					postProcessCallback(i, info, true)
				} else {
					//DLog("Skipping %@: %@",type,serverId)
					i.postSyncAction = PostSyncAction.doNothing.rawValue
					postProcessCallback(i, info, false)
				}
			}
		}

		if !createNewItems { return }

		for serverId in idsOfItems {
			if let info = idsToInfo[serverId] {
				DLog("Creating %@: %@", entityName, serverId)
				let i = NSEntityDescription.insertNewObject(forEntityName: entityName, into: server.managedObjectContext!) as! T
				i.serverId = serverId
				i.postSyncAction = PostSyncAction.isNew.rawValue
				i.apiServer = server

				i.createdAt = DataItem.parseGH8601(info["created_at"] as? String) ?? now
				i.updatedAt = DataItem.parseGH8601(info["updated_at"] as? String) ?? i.createdAt

				postProcessCallback(i, info, true)
			}
		}
	}

	static func items<T: DataItem>(of type: T.Type, surviving: Bool, in moc: NSManagedObjectContext, prefetchRelationships: [String]? = nil) -> [T] {
		let f = NSFetchRequest<T>(entityName: String(describing: type))
		f.relationshipKeyPathsForPrefetching = prefetchRelationships
		f.includesSubentities = false
		if surviving {
			f.returnsObjectsAsFaults = false
			f.predicate = PostSyncAction.delete.excludingPredicate
		} else {
			f.returnsObjectsAsFaults = true
			f.predicate = PostSyncAction.delete.matchingPredicate
		}
		return try! moc.fetch(f)
	}

	static func newOrUpdatedItems<T: DataItem>(of type: T.Type, in moc: NSManagedObjectContext) -> [T] {
		let f = NSFetchRequest<T>(entityName: String(describing: type))
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		f.predicate = NSCompoundPredicate(type: .or, subpredicates: [PostSyncAction.isNew.matchingPredicate, PostSyncAction.isUpdated.matchingPredicate])
		return try! moc.fetch(f)
	}

	static func updatedItems<T: DataItem>(of type: T.Type, in moc: NSManagedObjectContext) -> [T] {
		let f = NSFetchRequest<T>(entityName: String(describing: type))
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		f.predicate = PostSyncAction.isUpdated.matchingPredicate
		return try! moc.fetch(f)
	}

	static func newItems<T: DataItem>(of type: T.Type, in moc: NSManagedObjectContext) -> [T] {
		let f = NSFetchRequest<T>(entityName: String(describing: type))
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		f.predicate = PostSyncAction.isNew.matchingPredicate
		return try! moc.fetch(f)
	}

	static func nukeDeletedItems(in moc: NSManagedObjectContext) {

		func nukeDeletedItems<T: DataItem>(of type: T.Type, in moc: NSManagedObjectContext) -> Int {
			let discarded = items(of: type, surviving: false, in: moc)
			if discarded.count > 0 {
				DLog("Nuking %@ %@ items marked for deletion", discarded.count, String(describing: type))
				for i in discarded {
					moc.delete(i)
				}
			}
			return discarded.count
		}

		var count = 0
		count += nukeDeletedItems(of: Repo.self, in: moc)
		count += nukeDeletedItems(of: PullRequest.self, in: moc)
		count += nukeDeletedItems(of: PRStatus.self, in: moc)
		count += nukeDeletedItems(of: PRComment.self, in: moc)
		count += nukeDeletedItems(of: PRLabel.self, in: moc)
		count += nukeDeletedItems(of: Issue.self, in: moc)
		count += nukeDeletedItems(of: Team.self, in: moc)
		count += nukeDeletedItems(of: Review.self, in: moc)
		count += nukeDeletedItems(of: Reaction.self, in: moc)
		DLog("Nuked total %@ items marked for deletion", count)
	}

	static func countItems<T: DataItem>(of type: T.Type, in moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest<T>(entityName: String(describing: type))
		f.includesSubentities = false
		return try! moc.count(for: f)
	}

	static func add<T: ListableItem>(criterion: GroupingCriterion?, toFetchRequest: NSFetchRequest<T>, originalPredicate: NSPredicate, in moc: NSManagedObjectContext, includeAllGroups: Bool = false) {
		var andPredicates = [NSPredicate]()
		if let c = criterion {
			andPredicates.append(c.addCriterion(to: originalPredicate, in: moc))
		} else {
			andPredicates.append(originalPredicate)
		}
		if !includeAllGroups && criterion?.repoGroup == nil {
			for otherGroup in Repo.allGroupLabels(in: moc) {
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

	// Single-purpose derivation from the excellent SAMAdditions:
	// https://github.com/soffes/SAMCategories/blob/master/SAMCategories/NSDate%2BSAMAdditions.m
	// Main thread only
	private static var timeData = tm()
	private static var dateParserHolder = "                   +0000".cString(using: String.Encoding.ascii)!
	private static func parseGH8601(_ iso8601: String?) -> Date? {

		guard let i = iso8601, i.count > 18 else { return nil }

		memcpy(&dateParserHolder, i, 19)
		strptime(dateParserHolder, "%FT%T%z", &timeData)

		let t = mktime(&timeData)
		return Date(timeIntervalSince1970: TimeInterval(t))
	}
}
