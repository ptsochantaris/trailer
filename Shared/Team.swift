
import CoreData

final class Team: DataItem {

    @NSManaged var slug: String?
    @NSManaged var organisationLogin: String?
	@NSManaged var calculatedReferral: String?

	class func syncTeamsWithInfo(data: [[NSObject : AnyObject]]?, apiServer: ApiServer) {

		itemsWithInfo(data, type: "Team", fromServer: apiServer) { item, info, isNewOrUpdated in
			let t = item as! Team
			let slug = info["slug"] as? String ?? ""
			let org = info["organization"]?["login"] as? String ?? ""
			t.slug = slug
			t.organisationLogin = org
			if slug.isEmpty || org.isEmpty {
				t.calculatedReferral = nil
			} else {
				t.calculatedReferral = "@\(org)/\(slug)"
			}
			t.postSyncAction = PostSyncAction.DoNothing.rawValue
		}
	}
}
