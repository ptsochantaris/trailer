
import CoreData

final class Team: DataItem {

    @NSManaged var slug: String?
    @NSManaged var organisationLogin: String?
	@NSManaged var calculatedReferral: String?

	class func syncTeams(from data: [[NSObject : AnyObject]]?, server: ApiServer) {

		items(with: data, type: "Team", server: server) { item, info, isNewOrUpdated in
			let t = item as! Team
			let slug = S(info["slug"] as? String)
			let org = S(info["organization"]?["login"] as? String)
			t.slug = slug
			t.organisationLogin = org
			if slug.isEmpty || org.isEmpty {
				t.calculatedReferral = nil
			} else {
				t.calculatedReferral = "@\(org)/\(slug)"
			}
			t.postSyncAction = PostSyncAction.doNothing.rawValue
		}
	}
}
