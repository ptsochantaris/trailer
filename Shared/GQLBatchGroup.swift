import Foundation

struct GQLBatchGroup: GQLScanning {
    let id: UUID
    let name: String
    
    private let idList: [String]
    private let templateGroup: GQLGroup
        
    init(templateGroup: GQLGroup, idList: [String]) {
        self.id = UUID()
        self.name = "nodes"
        self.templateGroup = templateGroup
        self.idList = idList
        assert(idList.count <= 100)
    }
    
    init(cloning: GQLBatchGroup, templateGroup: GQLGroup, idList: [String]) {
        self.id = cloning.id
        self.name = cloning.name
        self.idList = idList
        self.templateGroup = templateGroup
        assert(idList.count <= 100)
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
        let count = idList.count
        return count + count * templateGroup.nodeCost
    }
    
    var queryText: String {
        "nodes(ids: [\"" + idList.joined(separator: "\",\"") + "\"]) { " + templateGroup.fields.map(\.queryText).joined(separator: " ") + " }"
    }

    var fragments: LinkedList<GQLFragment> {
        templateGroup.fragments
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

        return extraQueries
    }
}
