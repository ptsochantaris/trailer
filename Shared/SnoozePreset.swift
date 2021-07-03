import CoreData

final class SnoozePreset: NSManagedObject {

	@NSManaged var day: Int64
	@NSManaged var hour: Int64
	@NSManaged var minute: Int64

	@NSManaged var sortOrder: Int64
	@NSManaged var duration: Bool

	@NSManaged var wakeOnComment: Bool
	@NSManaged var wakeOnMention: Bool
	@NSManaged var wakeOnStatusChange: Bool

	@NSManaged var appliedToPullRequests: Set<PullRequest>
	@NSManaged var appliedToIssues: Set<Issue>

	var listDescription: String {
		if duration {
			var resultItems = [String]()
			if day > 0 {
				resultItems.append(day > 1 ? "\(day) days" : "1 day")
			}
			if hour > 0 {
				resultItems.append(hour > 1 ? "\(hour) hours" : "1 hour")
			}
			if minute > 0 {
				resultItems.append(minute > 1 ? "\(minute) minutes" : "1 minute")
			}
			if resultItems.isEmpty {
				if wakeOnComment || wakeOnMention || wakeOnStatusChange {
					return "Until event or manual wake"
				} else {
					return "Until manual wake"
				}
			}
			return "For \(resultItems.joined(separator: ", "))"
		} else {
			var result = "Until "
			switch day {
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
			result.append(String(format: "%02d", hour))
			result.append(":")
			result.append(String(format: "%02d", minute))
			return result
		}
	}

	func wakeUpAllAssociatedItems() {
		for p in appliedToPullRequests {
			p.wakeUp()
		}
		for i in appliedToIssues {
			i.wakeUp()
		}
	}

	static func allSnoozePresets(in moc: NSManagedObjectContext) -> [SnoozePreset] {
		let f = NSFetchRequest<SnoozePreset>(entityName: "SnoozePreset")
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		f.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
		return try! moc.fetch(f)
	}

	static func newSnoozePreset(in moc: NSManagedObjectContext) -> SnoozePreset {
		let s = NSEntityDescription.insertNewObject(forEntityName: "SnoozePreset", into: moc) as! SnoozePreset
		s.duration = true
		s.sortOrder = Int64.max
		setSortOrders(in: moc)
		return s
	}

	static func setSortOrders(in moc: NSManagedObjectContext) {
		// Sanity to prevent sorting confusion later
		var c: Int64 = 0
		for i in allSnoozePresets(in: moc) {
			i.sortOrder = c
			c += 1
		}
	}

	var wakeupDateFromNow: Date {

		let now = Date()
		
		if duration {

			if day == 0 && hour == 0 && minute == 0 {
				return .distantFuture
			}
			var wakeupTimeFromNow = TimeInterval(minute)*60.0
			wakeupTimeFromNow += TimeInterval(hour)*60.0*60.0
			wakeupTimeFromNow += TimeInterval(day)*60.0*60.0*24.0
			return Date(timeIntervalSinceNow: wakeupTimeFromNow)

		} else {

			var c = DateComponents()
			c.minute = Int(minute)
			c.hour = Int(hour)
			if day > 0 {
				c.weekday = Int(day)
			}
			return Calendar.current.nextDate(after: now, matching: c, matchingPolicy: .nextTimePreservingSmallerComponents)!
		}
	}

	static var archivedPresets: [[String : NSObject]] {
		var archivedData = [[String : NSObject]]()
		for a in SnoozePreset.allSnoozePresets(in: DataManager.main) {
			var presetData = [String : NSObject]()
			for (k , _) in a.entity.attributesByName {
				if let v = a.value(forKey: k) as? NSObject {
					presetData[k] = v
				}
			}
			archivedData.append(presetData)
		}
		return archivedData
	}

	static func configure(from archive: [[String : NSObject]]) -> Bool {

		let tempMoc = DataManager.buildChildContext()

		for apiServer in allSnoozePresets(in: tempMoc) {
			tempMoc.delete(apiServer)
		}

		for presetData in archive {
			let a = newSnoozePreset(in: tempMoc)
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
		} catch {
			return false
		}
	}
}
