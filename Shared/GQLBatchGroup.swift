import Foundation

extension GraphQL {
    struct BatchGroup: GQLScanning {
        let id: UUID
        let name: String

        private let idList: [String]
        private let templateGroup: Group

        init(templateGroup: Group, idList: [String]) {
            id = UUID()
            name = "nodes"
            self.templateGroup = templateGroup
            self.idList = idList
            assert(idList.count <= 100)
        }

        private init(cloning: BatchGroup, templateGroup: Group, rootId: String) {
            id = cloning.id
            name = cloning.name
            self.idList = [rootId]
            self.templateGroup = templateGroup
            assert(idList.count <= 100)
        }

        func asShell(for element: GQLElement, batchRootId: String?) -> GQLElement? {
            if id == element.id {
                return element
            }

            if let batchRootId, let shellGroup = templateGroup.asShell(for: element, batchRootId: nil) as? Group {
                return BatchGroup(cloning: self, templateGroup: shellGroup, rootId: batchRootId)
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

        var fragments: LinkedList<Fragment> {
            templateGroup.fragments
        }

        func scan(query: Query, pageData: Any, parent: Node?) async -> LinkedList<Query> {
            guard let nodes = pageData as? [Any] else { return LinkedList<Query>() }

            let extraQueries = LinkedList<Query>()

            for pageData in nodes {
                if let pageData = pageData as? JSON {
                    let newQueries = await templateGroup.scan(query: query, pageData: pageData, parent: parent)
                    extraQueries.append(contentsOf: newQueries)
                }
            }

            return extraQueries
        }
    }
}
