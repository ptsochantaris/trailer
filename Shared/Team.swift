
import CoreData

@objc (Team)
class Team: DataItem {

    @NSManaged var slug: String?
    @NSManaged var organisationLogin: String?

	class func teamWithInfo(info: NSDictionary, fromApiServer: ApiServer) -> Team {
		let serverId = info.ofk("id") as NSNumber
		var t = Team.itemOfType("Team", serverId: serverId, fromServer: fromApiServer) as? Team
		if t==nil {
			DLog("Creating Team: %@", serverId)
			t = NSEntityDescription.insertNewObjectForEntityForName("Team", inManagedObjectContext: fromApiServer.managedObjectContext!) as? Team
			t!.serverId = serverId
			t!.updatedAt = NSDate.distantPast() as? NSDate
			t!.createdAt = NSDate.distantPast() as? NSDate
			t!.apiServer = fromApiServer
		} else {
			DLog("Updating Team: %@", serverId)
		}

		t!.slug = info.ofk("slug") as? String
		t!.organisationLogin = info.ofk("organization")?.ofk("login") as? String
		t!.postSyncAction = PostSyncAction.DoNothing.rawValue
		return t!
	}
}
