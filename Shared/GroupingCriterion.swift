
import CoreData

final class GroupingCriterion {

	let apiServerId: NSManagedObjectID?
	let repoIds: [NSManagedObjectID]?
	let label: String?

	init(apiServerId: NSManagedObjectID?, repoIds: [NSManagedObjectID]?) {
		self.apiServerId = apiServerId
		self.repoIds = repoIds
		if let aid = apiServerId, a = existingObjectWithID(aid) as? ApiServer {
			label = a.label
		} else if let rid = repoIds?.first, r = existingObjectWithID(rid) as? Repo {
			label = r.fullName
		} else {
			label = nil
		}
	}

	func isRelatedTo(i: ListableItem) -> Bool {
		if let aid = apiServerId {
			if i.apiServer.objectID != aid {
				return false
			}
		}
		if let rids = repoIds {
			var gotIt = false
			for rid in rids {
				if i.repo.objectID == rid {
					gotIt = true
				}
			}
			return gotIt
		}
		return true
	}

	func addCriterionToPredicate(p: NSPredicate, inMoc: NSManagedObjectContext) -> NSPredicate {

		var andPredicates = [p]

		if let a = apiServerId, server = try! inMoc.existingObjectWithID(a) as? ApiServer {
			let r = NSPredicate(format: "apiServer == %@", server)
			andPredicates.append(r)
		}

		if let r = repoIds where r.count > 0 {
			var orPredicates = [NSPredicate]()
			for rid in r {
				if let repo = try! inMoc.existingObjectWithID(rid) as? Repo {
					let p = NSPredicate(format: "repo == %@", repo)
					orPredicates.append(p)
				}
			}
			if orPredicates.count > 0 {
				let orRepoPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: orPredicates)
				andPredicates.append(orRepoPredicate)
			}
		}

		return NSCompoundPredicate(andPredicateWithSubpredicates: andPredicates)
	}
}
