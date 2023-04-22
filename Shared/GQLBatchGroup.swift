import Foundation

struct GQLBatchGroup: GQLScanning {
    let name = "nodes"

    private let idsToGroups: [String: GQLGroup]
    private let originalTemplate: GQLGroup
    private let nextCount: Int
    private let batchLimit: Int

    init(templateGroup: GQLGroup, idList: [String], startingCount: Int = 0, batchLimit: Int) {
        var index = startingCount
        var id2g = [String: GQLGroup]()
        id2g.reserveCapacity(idList.count)
        for id in idList {
            id2g[id] = GQLGroup(group: templateGroup, name: "\(templateGroup.name)\(index)")
            index += 1
        }
        originalTemplate = templateGroup
        idsToGroups = id2g
        nextCount = index
        self.batchLimit = batchLimit
    }
    
    static func recommendedLimit(for template: GQLGroup) -> Int {
        let templateCost = Float(template.nodeCost)
        let estimatedBatchSize = (500000 / templateCost).rounded(.down)
        return min(100, max(1, Int(estimatedBatchSize)))
    }
    
    var nodeCost: Int {
        if let templateGroup = idsToGroups.values.first {
            let count = pageOfIds.count
            return count + count * templateGroup.nodeCost
        } else {
            return 0
        }
    }
    
    var queryText: String {
        if let templateGroup = idsToGroups.values.first {
            return "nodes(ids: [\"" + pageOfIds.joined(separator: "\",\"") + "\"]) { " + templateGroup.fields.map(\.queryText).joined(separator: " ") + " }"
        } else {
            return ""
        }
    }

    var fragments: LinkedList<GQLFragment> {
        let res = LinkedList<GQLFragment>()
        for list in idsToGroups.values {
            res.append(contentsOf: list.fragments)
        }
        return res
    }

    private var pageOfIds: ArraySlice<String> {
        let k = idsToGroups.keys.sorted()
        let chunkLimit = min(batchLimit, k.count)
        return k[0 ..< chunkLimit]
    }

    func scan(query: GQLQuery, pageData: Any, parent: GQLNode?) async -> LinkedList<GQLQuery> {
        // DLog("\(query.logPrefix)Scanning batch group \(name)")
        guard let nodes = pageData as? [Any] else { return LinkedList<GQLQuery>() }

        let extraQueries = LinkedList<GQLQuery>()

        let page = pageOfIds
        let newIds = idsToGroups.keys.filter { !page.contains($0) }
        if !newIds.isEmpty {
            let nextPage = GQLQuery(name: query.name, rootElement: GQLBatchGroup(templateGroup: originalTemplate, idList: newIds, startingCount: nextCount, batchLimit: batchLimit), parent: parent)
            extraQueries.append(nextPage)
        }

        for n in nodes {
            if let n = n as? [AnyHashable: Any], let id = n["id"] as? String, let group = idsToGroups[id] {
                let newQueries = await group.scan(query: query, pageData: n, parent: parent)
                extraQueries.append(contentsOf: newQueries)
            }
        }

        if extraQueries.count > 0 {
            DLog("\(query.logPrefix)(Group: \(name)) - Will need further paging")
        }
        return extraQueries
    }
}
