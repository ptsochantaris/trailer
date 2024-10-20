import CoreData
import TrailerJson

final class Team: DataItem {
    @NSManaged var slug: String?
    @NSManaged var organisationLogin: String?
    @NSManaged var calculatedReferral: String?

    override static var typeName: String { "Team" }

    static func team(with slug: String, in moc: NSManagedObjectContext) -> Team? {
        let f = NSFetchRequest<Team>(entityName: "Team")
        f.fetchLimit = 1
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        f.predicate = NSPredicate(format: "slug == %@", slug)
        return try? moc.fetch(f).first
    }

    static func syncTeams(from data: [TypedJson.Entry]?, serverId: NSManagedObjectID, moc: NSManagedObjectContext) async {
        await v3items(with: data, type: Team.self, serverId: serverId, moc: moc) { item, info, _, _ in
            let slug = info.potentialString(named: "slug").orEmpty
            let org = (info.potentialObject(named: "organization")?.potentialString(named: "login")).orEmpty
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
