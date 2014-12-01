
@objc (PRLabel)
class PRLabel: DataItem {

    @NSManaged var color: NSNumber?
    @NSManaged var name: String?
    @NSManaged var url: String?

    @NSManaged var pullRequest: PullRequest

	class func labelWithName(name: String, fromServer: ApiServer) -> PRLabel? {
		let f = NSFetchRequest(entityName: "PRLabel")
		f.fetchLimit = 1
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "name == %@ and apiServer == %@", name, fromServer)
		let res = fromServer.managedObjectContext?.executeFetchRequest(f, error: nil) as [PRLabel]
		return res.first
	}

	class func labelWithInfo(info: NSDictionary, fromServer: ApiServer) -> PRLabel {
		let name = info.ofk("name") as String?
		var l = PRLabel.labelWithName(name!, fromServer: fromServer)
		if(l==nil) {
			l = NSEntityDescription.insertNewObjectForEntityForName("PRLabel", inManagedObjectContext: fromServer.managedObjectContext!) as? PRLabel
			l!.name = name
			l!.serverId = NSNumber(int: 0)
			l!.updatedAt = NSDate.distantPast() as? NSDate
			l!.createdAt = NSDate.distantPast() as? NSDate
			l!.apiServer = fromServer
		}
		l!.url = info.ofk("url") as String?
		if let c = info.ofk("color") as String? {
			l!.color = NSNumber(unsignedInt: c.parseFromHex())
		} else {
			l!.color = NSNumber(integer: 0)
		}
		l!.postSyncAction = NSNumber(integer: PostSyncAction.DoNothing.rawValue)
		return l!
	}

	func colorForDisplay() -> COLOR_CLASS {
		if let c = self.color?.unsignedLongLongValue {
			let red: UInt64 = (c & 0xFF0000)>>16
			let green: UInt64 = (c & 0x00FF00)>>8
			let blue: UInt64 = c & 0x0000FF
			let r = CGFloat(red)/255.0
			let g = CGFloat(green)/255.0
			let b = CGFloat(blue)/255.0
			return COLOR_CLASS(red: r, green: g, blue: b, alpha: 1.0)
		} else {
			return COLOR_CLASS.blackColor()
		}
	}
}
