
import CoreData

final class Team: DataItem {

    @NSManaged var slug: String?
    @NSManaged var organisationLogin: String?
	@NSManaged var calculatedReferral: String?

	static func syncTeams(from data: [[AnyHashable : Any]]?, server: ApiServer) {

		items(with: data, type: Team.self, server: server) { item, info, isNewOrUpdated in
			let slug = S(info["slug"] as? String)
			let org = S((info["organization"] as? [AnyHashable : Any])?["login"] as? String)
			item.slug = slug
			item.organisationLogin = org
			if slug.isEmpty || org.isEmpty {
				item.calculatedReferral = nil
			} else {
				item.calculatedReferral = "@\(org)/\(slug)"
			}
			item.postSyncAction = PostSyncAction.doNothing.rawValue
		}
	}
}
