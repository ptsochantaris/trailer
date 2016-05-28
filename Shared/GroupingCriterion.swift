
import CoreData

final class GroupingCriterion {

	let apiServerId: NSManagedObjectID?
	let repoGroup: String?

	init(apiServerId: NSManagedObjectID?) {
		self.apiServerId = apiServerId
		self.repoGroup = nil
	}

	init(repoGroup: String) {
		self.apiServerId = nil
		self.repoGroup = repoGroup
	}

	var label: String {
		if let r = repoGroup {
			return r
		} else if let aid = apiServerId, a = existingObjectWithID(aid) as? ApiServer {
			return a.label ?? "<none>"
		} else {
			return "<none>"
		}
	}

	var relatedServerFailed: Bool {
		if let aid = apiServerId, a = existingObjectWithID(aid) as? ApiServer where !(a.lastSyncSucceeded?.boolValue ?? true) {
			return true
		}
		if let r = repoGroup {
			for repo in Repo.reposForGroup(r, inMoc: mainObjectContext) {
				if !(repo.apiServer.lastSyncSucceeded?.boolValue ?? true) {
					return true
				}
			}
		}
		return false
	}

	func isRelatedTo(i: ListableItem) -> Bool {
		if let aid = apiServerId {
			if i.apiServer.objectID != aid {
				return false
			}
		} else if let r = repoGroup {
			if let l = i.repo.groupLabel {
				return r == l
			} else {
				return false
			}
		}
		return true
	}

	func addCriterionToPredicate(p: NSPredicate, inMoc: NSManagedObjectContext) -> NSPredicate {

		if let a = apiServerId, server = try! inMoc.existingObjectWithID(a) as? ApiServer {
			let np = NSPredicate(format: "apiServer == %@", server)
			return NSCompoundPredicate(andPredicateWithSubpredicates: [np, p])
		} else if let r = repoGroup {
			let np = NSPredicate(format: "repo.groupLabel == %@", r)
			return NSCompoundPredicate(andPredicateWithSubpredicates: [np, p])
		} else {
			return p
		}
	}
}
