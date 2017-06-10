
import CoreData

final class CacheEntry: NSManagedObject {

	@NSManaged var etag: String
	@NSManaged var code: Int64
	@NSManaged var data: Data
	@NSManaged var lastTouched: Date
	@NSManaged var lastFetched: Date
	@NSManaged var key: String
	@NSManaged var headers: Data

	static let cacheMoc = DataManager.buildParallelContext()

	var actualHeaders: [AnyHashable : Any] {
		return NSKeyedUnarchiver.unarchiveObject(with: headers) as! [AnyHashable : Any]
	}

	var parsedData: Any? {
		return try? JSONSerialization.jsonObject(with: data, options: [])
	}

	class func setEntry(key: String, code: Int64, etag: String, data: Data, headers: [AnyHashable : Any]) {
		var e = entry(for: key)
		if e == nil {
			e = NSEntityDescription.insertNewObject(forEntityName: "CacheEntry", into: cacheMoc) as? CacheEntry
			e!.key = key
		}
		let E = e!
		E.code = code
		E.data = data
		E.etag = etag
		E.headers = NSKeyedArchiver.archivedData(withRootObject: headers)
		E.lastFetched = Date()
		E.lastTouched = Date()
	}

	private static let entryFetch: NSFetchRequest<CacheEntry> = {
		let f = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		f.fetchLimit = 1
		return f
	}()

	class func entry(for key: String) -> CacheEntry? {
		entryFetch.predicate = NSPredicate(format: "key == %@", key)
		if let e = try! cacheMoc.fetch(entryFetch).first {
			e.lastTouched = Date()
			return e
		} else {
			return nil
		}
	}

	class func cleanAndCheckpoint() {
		let f = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
		f.returnsObjectsAsFaults = true
		f.includesSubentities = false
		let date = Date(timeIntervalSinceNow: -3600.0*24.0*7.0) as CVarArg // week-old
		f.predicate = NSPredicate(format: "lastTouched < %@", date)
		for e in try! cacheMoc.fetch(f) {
			DLog("Expiring unused cache entry for key %@", e.key)
			cacheMoc.delete(e)
		}
		if cacheMoc.hasChanges {
			try? cacheMoc.save()
		}
	}

	class func markFetched(for key: String) {
		if let e = entry(for: key) {
			e.lastFetched = Date()
		}
	}
}
