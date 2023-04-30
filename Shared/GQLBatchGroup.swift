import Foundation

struct GQLBatchGroup: GQLScanning {
    let id: UUID
    let name: String
    let batchLimit: Int

    private let idList: [String]
    private let templateGroup: GQLGroup
        
    init(templateGroup: GQLGroup, idList: [String]) {
        id = UUID()
        name = "nodes"
        batchLimit = templateGroup.recommendedLimit
        self.templateGroup = templateGroup
        self.idList = idList        
    }
    
    init(cloning: GQLBatchGroup, templateGroup: GQLGroup, idList: [String]) {
        self.id = cloning.id
        self.name = cloning.name
        self.idList = idList
        self.templateGroup = templateGroup
        self.batchLimit = cloning.batchLimit
    }
    
    func asShell(for element: GQLElement) -> GQLElement? {
        if id == element.id {
            return element
        }
        
        if let shellGroup = templateGroup.asShell(for: element) as? GQLGroup {
            return GQLBatchGroup(cloning: self, templateGroup: shellGroup, idList: idList)
        }
        
        return nil
    }
        
    var nodeCost: Int {
        let count = min(idList.count, batchLimit)
        return count + count * templateGroup.nodeCost
    }
    
    var queryText: String {
        "nodes(ids: [\"" + pageOfIds.joined(separator: "\",\"") + "\"]) { " + templateGroup.fields.map(\.queryText).joined(separator: " ") + " }"
    }

    var fragments: LinkedList<GQLFragment> {
        templateGroup.fragments
    }

    private var pageOfIds: ArraySlice<String> {
        idList.prefix(batchLimit)
    }
    
    private var remainingIds: ArraySlice<String> {
        idList.dropFirst(batchLimit)
    }

    func scan(query: GQLQuery, pageData: Any, parent: GQLNode?) async -> LinkedList<GQLQuery> {
        guard let nodes = pageData as? [Any] else { return LinkedList<GQLQuery>() }

        let extraQueries = LinkedList<GQLQuery>()

        for pageData in nodes {
            if let pageData = pageData as? [AnyHashable: Any] {
                let newQueries = await templateGroup.scan(query: query, pageData: pageData, parent: parent)
                extraQueries.append(contentsOf: newQueries)
            }
        }

        let newIds = remainingIds
        if !newIds.isEmpty {
            let nextPage = GQLQuery(name: query.name, rootElement: GQLBatchGroup(templateGroup: templateGroup, idList: Array(newIds)), parent: parent)
            extraQueries.append(nextPage)
        }

        if extraQueries.count > 0 {
            DLog("\(query.logPrefix)(Group: \(name)) - Will need to perform \(extraQueries.count) more queries")
        }
        return extraQueries
    }
}
