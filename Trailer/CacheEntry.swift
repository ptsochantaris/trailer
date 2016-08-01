
import CoreData

struct CacheUnit {
	let data: Data
	let code: Int
	let etag: String
	let headers: Data
	let lastFetched: Date

	func actualHeaders() -> [NSObject : AnyObject] {
		return NSKeyedUnarchiver.unarchiveObject(with: headers) as! [NSObject : AnyObject]
	}

	func parsedData() -> AnyObject? {
		return try? JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions())
	}
}

final class CacheEntry: NSManagedObject {

	@NSManaged var etag: String
	@NSManaged var code: NSNumber
	@NSManaged var data: Data
	@NSManaged var lastTouched: Date
	@NSManaged var lastFetched: Date
	@NSManaged var key: String
	@NSManaged var headers: Data

	func cacheUnit() -> CacheUnit {
		return CacheUnit(data: data, code: code.intValue, etag: etag, headers: headers, lastFetched: lastFetched)
	}

	class func setEntry(_ key: String, code: Int, etag: String, data: Data, headers: [NSObject : AnyObject]) {
		var e = entryForKey(key)
		if e == nil {
			e = NSEntityDescription.insertNewObject(forEntityName: "CacheEntry", into: mainObjectContext) as? CacheEntry
			e!.key = key
		}
		e!.code = code
		e!.data = data
		e!.etag = etag
		e!.headers = NSKeyedArchiver.archivedData(withRootObject: headers)
		e!.lastFetched = Date()
		e!.lastTouched = Date()
	}

	class func entryForKey(_ key: String) -> CacheEntry? {
		let f = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
		f.fetchLimit = 1
		f.predicate = NSPredicate(format: "key == %@", key)
		f.returnsObjectsAsFaults = false
		if let e = try! mainObjectContext.fetch(f).first {
			e.lastTouched = Date()
			return e
		} else {
			return nil
		}
	}

	class func cleanOldEntriesInMoc(_ moc: NSManagedObjectContext) {
		let f = NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
		f.returnsObjectsAsFaults = true
		f.predicate = NSPredicate(format: "lastTouched < %@", Date().addingTimeInterval(-3600.0*24.0*7.0)) // week-old
		for e in try! moc.fetch(f) {
			DLog("Expiring unused cache entry for key %@", e.key)
			moc.delete(e)
		}
	}

	class func markKeyAsFetched(_ key: String) {
		if let e = entryForKey(key) {
			e.lastFetched = Date()
		}
	}
}
