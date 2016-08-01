
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
			if let d = day?.intValue {
				resultItems.append(d > 1 ? "\(d) days" : "1 day")
			}
			if let h = hour?.intValue {
				resultItems.append(h > 1 ? "\(h) hours" : "1 hour")
			}
			if let m = minute?.intValue {
				resultItems.append(m > 1 ? "\(m) minutes" : "1 minute")
			}
			if resultItems.count == 0 {
				if Settings.snoozeWakeOnComment || Settings.snoozeWakeOnMention || Settings.snoozeWakeOnStatusUpdate {
					return "Until event or manual wake"
				} else {
					return "Until manual wake"
				}
			}
			return "For \(resultItems.joined(separator: ", "))"
		} else {
			var result = "Until "
			if let d = day?.intValue {
				switch d {
				case 1:
					result.append("Sunday ")
				case 2:
					result.append("Monday ")
				case 3:
					result.append("Tuesday ")
				case 4:
					result.append("Wednesday ")
				case 5:
					result.append("Thursday ")
				case 6:
					result.append("Friday ")
				case 7:
					result.append("Saturday ")
				default:
					break
				}
			}
			result.append(String(format: "%02d", hour?.intValue ?? 0))
			result.append(":")
			result.append(String(format: "%02d", minute?.intValue ?? 0))
			return result
		}
	}

	class func allSnoozePresetsInMoc(_ moc: NSManagedObjectContext) -> [SnoozePreset] {
		let f = NSFetchRequest<SnoozePreset>(entityName: "SnoozePreset")
		f.returnsObjectsAsFaults = false
		f.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
		return try! moc.fetch(f)
	}

	class func newSnoozePresetInMoc(_ moc: NSManagedObjectContext) -> SnoozePreset {
		let s = NSEntityDescription.insertNewObject(forEntityName: "SnoozePreset", into: moc) as! SnoozePreset
		s.duration = true
		s.sortOrder = NSNumber(value: Int(Int16.max))
		setSortOrdersInMoc(moc)
		return s
	}

	class func setSortOrdersInMoc(_ moc: NSManagedObjectContext) {
		// Sanity to prevent sorting confusion later
		var c = 0
		for i in allSnoozePresetsInMoc(moc) {
			i.sortOrder = NSNumber(value: c)
			c += 1
		}
	}

	var wakeupDateFromNow: Date {

		let now = Date()
		
		if duration.boolValue {

			if day==nil && hour==nil && minute==nil {
				return Date.distantFuture
			}
			var now = now.timeIntervalSinceReferenceDate
			now += (minute?.doubleValue ?? 0.0)*60.0
			now += (hour?.doubleValue ?? 0.0)*60.0*60.0
			now += (day?.doubleValue ?? 0.0)*60.0*60.0*24.0
			return Date(timeIntervalSinceReferenceDate: now)

		} else {

			var c = DateComponents()
			c.minute = minute?.intValue ?? 0
			c.hour = hour?.intValue ?? 0
			if let d = day?.intValue {
				c.weekday = d
			}
			return Calendar.current.nextDate(after: now, matching: c, matchingPolicy: .nextTimePreservingSmallerComponents)!
		}
	}

	class func archivePresets() -> [[String:NSObject]] {
		var archivedData = [[String:NSObject]]()
		for a in SnoozePreset.allSnoozePresetsInMoc(mainObjectContext) {
			var presetData = [String:NSObject]()
			for (k , _) in a.entity.attributesByName {
				if let v = a.value(forKey: k) as? NSObject {
					presetData[k] = v
				}
			}
			archivedData.append(presetData)
		}
		return archivedData
	}

	class func configureFromArchive(_ archive: [[String : NSObject]]) -> Bool {

		let tempMoc = DataManager.childContext()

		for apiServer in allSnoozePresetsInMoc(tempMoc) {
			tempMoc.delete(apiServer)
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
