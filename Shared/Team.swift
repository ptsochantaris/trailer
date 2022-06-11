import CoreData

final class Team: DataItem {
    @NSManaged var slug: String?
    @NSManaged var organisationLogin: String?
    @NSManaged var calculatedReferral: String?

    static func team(with slug: String, in moc: NSManagedObjectContext) -> Team? {
        let f = NSFetchRequest<Team>(entityName: "Team")
        f.fetchLimit = 1
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        f.predicate = NSPredicate(format: "slug == %@", slug)
        return try? moc.fetch(f).first
    }

    static func syncTeams(from data: [[AnyHashable: Any]]?, server: ApiServer) {
        items(with: data, type: Team.self, server: server) { item, info, _ in
            let slug = S(info["slug"] as? String)
            let org = S((info["organization"] as? [AnyHashable: Any])?["login"] as? String)
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
