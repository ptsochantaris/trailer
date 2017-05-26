
import CoreData

struct CacheUnit {
	let data: Data
	let code: Int64
	let etag: String
	let headers: Data
	let lastFetched: Date

	var actualHeaders: [AnyHashable : Any] {
		return NSKeyedUnarchiver.unarchiveObject(with: headers) as! [AnyHashable : Any]
	}

	var parsedData: Any? {
		return try? JSONSerialization.jsonObject(with: data, options: [])
	}
}

final class CacheEntry: NSManagedObject {

	@NSManaged var etag: String
	@NSManaged var code: Int64
	@NSManaged var data: Data
	@NSManaged var lastTouched: Date
	@NSManaged var lastFetched: Date
	@NSManaged var key: String
	@NSManaged var headers: Data

	var cacheUnit: CacheUnit {
		return CacheUnit(data: data, code: code, etag: etag, headers: headers, lastFetched: lastFetched)
	}

	class func setEntry(key: String, code: Int64, etag: String, data: Data, headers: [AnyHashable : Any], in moc: NSManagedObjectContext) {
		var e = entry(for: key, in: moc)
		if e == nil {
			e = NSEntityDescription.insertNewObject(forEntityName: "CacheEntry", into: moc) as? CacheEntry
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

	static let entryFetch: NSFetchRequest<CacheEntry> = {
		let f = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		f.fetchLimit = 1
		return f
	}()

	class func entry(for key: String, in moc: NSManagedObjectContext) -> CacheEntry? {
		entryFetch.predicate = NSPredicate(format: "key == %@", key)
		if let e = try! moc.fetch(entryFetch).first {
			e.lastTouched = Date()
			return e
		} else {
			return nil
		}
	}

	class func cleanOldEntries(in moc: NSManagedObjectContext) {
		let f = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
		f.returnsObjectsAsFaults = true
		f.includesSubentities = false
		let date = Date(timeIntervalSinceNow: -3600.0*24.0*7.0) as CVarArg // week-old
		f.predicate = NSPredicate(format: "lastTouched < %@", date)
		for e in try! moc.fetch(f) {
			DLog("Expiring unused cache entry for key %@", e.key)
			moc.delete(e)
		}
	}

	class func markFetched(for key: String, in moc: NSManagedObjectContext) {
		if let e = entry(for: key, in: moc) {
			e.lastFetched = Date()
		}
	}
}
