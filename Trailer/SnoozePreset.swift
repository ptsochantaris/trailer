
import CoreData

final class SnoozePreset: NSManagedObject {

	@NSManaged var day: NSNumber?
	@NSManaged var hour: NSNumber?
	@NSManaged var minute: NSNumber?

	@NSManaged var sortOrder: NSNumber

	@NSManaged var duration: NSNumber

	var listDescription: String {
		if duration.boolValue {
			var resultItems = [String]()
			if let d = day?.integerValue {
				resultItems.append(d > 1 ? "\(d) days" : "1 day")
			}
			if let h = hour?.integerValue {
				resultItems.append(h > 1 ? "\(h) hours" : "1 hour")
			}
			if let m = minute?.integerValue {
				resultItems.append(m > 1 ? "\(m) minutes" : "1 minute")
			}
			if resultItems.count == 0 {
				if Settings.snoozeWakeOnComment || Settings.snoozeWakeOnMention || Settings.snoozeWakeOnStatusUpdate {
					return "Until event or manual wake"
				} else {
					return "Until manual wake"
				}
			}
			return "For \(resultItems.joinWithSeparator(", "))"
		} else {
			var result = "Until "
			if let d = day?.integerValue {
				switch d {
				case 1:
					result.appendContentsOf("Sunday ")
				case 2:
					result.appendContentsOf("Monday ")
				case 3:
					result.appendContentsOf("Tuesday ")
				case 4:
					result.appendContentsOf("Wednesday ")
				case 5:
					result.appendContentsOf("Thursday ")
				case 6:
					result.appendContentsOf("Friday ")
				case 7:
					result.appendContentsOf("Saturday ")
				default:
					break
				}
			}
			result.appendContentsOf(String(format: "%02d", hour?.integerValue ?? 0))
			result.appendContentsOf(":")
			result.appendContentsOf(String(format: "%02d", minute?.integerValue ?? 0))
			return result
		}
	}

	class func allSnoozePresetsInMoc(moc: NSManagedObjectContext) -> [SnoozePreset] {
		let f = NSFetchRequest(entityName: "SnoozePreset")
		f.returnsObjectsAsFaults = false
		f.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
		return try! moc.executeFetchRequest(f) as! [SnoozePreset]
	}

	class func newSnoozePresetInMoc(moc: NSManagedObjectContext) -> SnoozePreset {
		let s = NSEntityDescription.insertNewObjectForEntityForName("SnoozePreset", inManagedObjectContext: moc) as! SnoozePreset
		s.duration = true
		s.sortOrder = NSNumber(integer: Int(Int16.max))
		setSortOrdersInMoc(moc)
		return s
	}

	class func setSortOrdersInMoc(moc: NSManagedObjectContext) {
		// Sanity to prevent sorting confusion later
		var c = 0
		for i in allSnoozePresetsInMoc(moc) {
			i.sortOrder = NSNumber(integer: c)
			c += 1
		}
	}

	var wakeupDateFromNow: NSDate {

		let now = NSDate()
		
		if duration.boolValue {

			if day==nil && hour==nil && minute==nil {
				return NSDate.distantFuture()
			}
			var now = now.timeIntervalSinceReferenceDate
			now += (minute?.doubleValue ?? 0.0)*60.0
			now += (hour?.doubleValue ?? 0.0)*60.0*60.0
			now += (day?.doubleValue ?? 0.0)*60.0*60.0*24.0
			return NSDate(timeIntervalSinceReferenceDate: now)

		} else {

			let c = NSDateComponents()
			c.minute = minute?.integerValue ?? 0
			c.hour = hour?.integerValue ?? 0
			if let d = day?.integerValue {
				c.weekday = d
			}
			return NSCalendar.currentCalendar().nextDateAfterDate(now, matchingComponents: c, options: .MatchNextTimePreservingSmallerUnits)!
		}
	}

	class func archivePresets() -> [[String:NSObject]] {
		var archivedData = [[String:NSObject]]()
		for a in SnoozePreset.allSnoozePresetsInMoc(mainObjectContext) {
			var presetData = [String:NSObject]()
			for (k , _) in a.entity.attributesByName {
				if let v = a.valueForKey(k) as? NSObject {
					presetData[k] = v
				}
			}
			archivedData.append(presetData)
		}
		return archivedData
	}

	class func configureFromArchive(archive: [[String : NSObject]]) -> Bool {

		let tempMoc = DataManager.tempContext()

		for apiServer in allSnoozePresetsInMoc(tempMoc) {
			tempMoc.deleteObject(apiServer)
		}

		for presetData in archive {
			let a = newSnoozePresetInMoc(tempMoc)
			let attributes = Array(a.entity.attributesByName.keys)
			for (k,v) in presetData {
				if attributes.contains(k) {
					a.setValue(v, forKey: k)
				}
			}
		}

		do {
			try tempMoc.save()
			return true
		} catch _ {
			return false
		}
	}
}
