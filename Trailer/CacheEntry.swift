
import CoreData

struct CacheUnit {
	let data: NSData
	let code: Int
	let etag: String
	let headers: NSData

	func actualHeaders() -> [NSObject : AnyObject] {
		return NSUnarchiver.unarchiveObjectWithData(headers) as! [NSObject : AnyObject]
	}
}

final class CacheEntry: NSManagedObject {

	@NSManaged var etag: String
	@NSManaged var code: NSNumber
	@NSManaged var data: NSData
	@NSManaged var lastTouched: NSDate
	@NSManaged var key: String
	@NSManaged var headers: NSData

	func cacheUnit() -> CacheUnit {
		return CacheUnit(data: data, code: code.integerValue, etag: etag, headers: headers)
	}

	class func setEntry(key: String, code: Int, etag: String, data: NSData, headers: [NSObject : AnyObject]) {
		var e = entryForKey(key)
		if e == nil {
			e = NSEntityDescription.insertNewObjectForEntityForName("CacheEntry", inManagedObjectContext: mainObjectContext) as? CacheEntry
			e!.key = key
			e!.lastTouched = NSDate()
		}
		e!.code = code
		e!.data = data
		e!.etag = etag
		e!.headers = NSArchiver.archivedDataWithRootObject(headers)
	}

	class func entryForKey(key: String) -> CacheEntry? {
		let f = NSFetchRequest(entityName: "CacheEntry")
		f.fetchLimit = 1
		f.predicate = NSPredicate(format: "key == %@", key)
		f.returnsObjectsAsFaults = false
		if let e = try! mainObjectContext.executeFetchRequest(f).first as? CacheEntry {
			e.lastTouched = NSDate()
			return e
		} else {
			return nil
		}
	}

	class func cleanOldEntries() {
		let f = NSFetchRequest(entityName: "CacheEntry")
		f.returnsObjectsAsFaults = true
		f.predicate = NSPredicate(format: "lastTouched < %@", NSDate().dateByAddingTimeInterval(-3600.0*24.0*7.0)) // week-old
		for e in try! mainObjectContext.executeFetchRequest(f) as! [CacheEntry] {
			DLog("Expiring unused cache entry for key %@", e.key)
			mainObjectContext.deleteObject(e)
		}
	}
}
