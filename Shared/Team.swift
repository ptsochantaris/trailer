
import CoreData

final class Team: DataItem {

    @NSManaged var slug: String?
    @NSManaged var organisationLogin: String?
	@NSManaged var calculatedReferral: String?

	class func teamWithInfo(info: [NSObject : AnyObject], fromApiServer: ApiServer) -> Team {
		let serverId = N(info, "id") as! NSNumber
		var t = Team.itemOfType("Team", serverId: serverId, fromServer: fromApiServer) as? Team
		if t==nil {
			DLog("Creating Team: %@", serverId)
			t = NSEntityDescription.insertNewObjectForEntityForName("Team", inManagedObjectContext: fromApiServer.managedObjectContext!) as? Team
			t!.serverId = serverId
			t!.updatedAt = never()
			t!.createdAt = never()
			t!.apiServer = fromApiServer
		} else {
			DLog("Updating Team: %@", serverId)
		}

		let slug = N(info, "slug") as? String ?? ""
		let org = N(N(info, "organization"), "login") as? String ?? ""
		t!.slug = slug
		t!.organisationLogin = org
		if slug.isEmpty || org.isEmpty {
			t!.calculatedReferral = nil
		} else {
			t!.calculatedReferral = "@\(org)/\(slug)"
		}
		t!.postSyncAction = PostSyncAction.DoNothing.rawValue
		return t!
	}
}
