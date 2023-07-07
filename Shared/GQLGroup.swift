import Foundation
import TrailerJson

extension GraphQL {
    struct Group: GQLScanning {
        enum Paging {
            case none, first(count: Int, paging: Bool), last(count: Int), max
        }

        typealias Param = (name: String, value: LosslessStringConvertible)

        let id: UUID
        let name: String
        let fields: [GQLElement]
        let paging: Paging
        private let extraParams: [Param]
        private let lastCursor: String?

        init(_ name: String, _ params: Param..., paging: Paging = .none, @GQLElementsBuilder fields: () -> [GQLElement]) {
            id = UUID()
            self.name = name
            self.fields = fields()
            self.paging = paging
            extraParams = params
            lastCursor = nil
        }

        private init(cloning group: Group, name: String? = nil, lastCursor: String? = nil, replacedFields: [GQLElement]? = nil) {
            id = group.id
            self.name = name ?? group.name
            fields = replacedFields ?? group.fields
            paging = group.paging
            extraParams = group.extraParams
            self.lastCursor = lastCursor
        }

        func asShell(for element: GQLElement, batchRootId _: String?) -> GQLElement? {
            if element.id == id {
                return element
            }

            let replacementFields = fields.compactMap { $0.asShell(for: element, batchRootId: nil) }
            if replacementFields.isEmpty {
                return nil
            }
            return Group(cloning: self, replacedFields: replacementFields)
        }

        var nodeCost: Int {
            let fieldCost = fields.reduce(0) { $0 + $1.nodeCost }
            switch paging {
            case .none:
                return fieldCost

            case .max:
                return 100 + fieldCost * 100

            case let .first(count, _), let .last(count):
                return count + fieldCost * count
            }
        }

        var recommendedLimit: Int {
            let templateCost = Float(nodeCost)
            let estimatedBatchSize = (500_000 / templateCost).rounded(.down)
            return min(100, max(1, Int(estimatedBatchSize)))
        }

        var queryText: String {
            var query = name
            let brackets = LinkedList<String>()

            switch paging {
            case .none:
                break

            case let .last(count):
                brackets.append("last: \(count)")

            case .max:
                brackets.append("first: 100")
                if let lastCursor {
                    brackets.append("after: \"\(lastCursor)\"")
                }

            case let .first(count, useCursor):
                brackets.append("first: \(count)")
                if useCursor, let lastCursor {
                    brackets.append("after: \"\(lastCursor)\"")
                }
            }

            for param in extraParams {
                if let value = param.value as? String, let firstChar = value.first, firstChar != "[", firstChar != "{" {
                    brackets.append("\(param.name): \"\(value)\"")
                } else {
                    brackets.append("\(param.name): \(param.value)")
                }
            }

            if brackets.count > 0 {
                query += "(" + brackets.joined(separator: ", ") + ")"
            }

            let fieldsText = "__typename " + fields.map(\.queryText).joined(separator: " ")

            switch paging {
            case .none:
                query += " { " + fieldsText + " }"

            case let .first(_, paging):
                if paging {
                    query += " { edges { node { " + fieldsText + " } cursor } pageInfo { hasNextPage } }"
                } else {
                    query += " { edges { node { " + fieldsText + " } } }"
                }

            case .max:
                query += " { edges { node { " + fieldsText + " } cursor } pageInfo { hasNextPage } }"

            case .last:
                query += " { edges { node { " + fieldsText + " } } }"
            }

            return query
        }

        var fragments: LinkedList<Fragment> {
            let res = LinkedList<Fragment>()
            for field in fields {
                res.append(contentsOf: field.fragments)
            }
            return res
        }

        private func scanNode(_ node: JSON, query: Query, parent: Node?, extraQueries: LinkedList<Query>) async throws {
            let thisObject: Node?

            if let o = Node(jsonPayload: node, parent: parent) {
                thisObject = o
                try await query.perNodeBlock?(o)

            } else { // we're a container, not an object, unwrap this level and recurse into it
                thisObject = parent
            }

            for field in fields {
                if let fragment = field as? Fragment {
                    try await fragment.scan(query: query, pageData: node, parent: thisObject, extraQueries: extraQueries)

                } else if let ingestable = field as? GQLScanning, let fieldData = node[field.name] {
                    try await ingestable.scan(query: query, pageData: fieldData, parent: thisObject, extraQueries: extraQueries)
                }
            }

            let count = extraQueries.count
            if count > 0 {
                if let thisObject {
                    DLog("\(query.logPrefix)(\(thisObject.elementType + ":" + thisObject.id) in: \(name)) will need further paging: \(count) new queries")
                } else {
                    DLog("\(query.logPrefix)(Node in: \(name)) will need further paging: \(count) new queries")
                }
            }
        }

        private func scanPage(_ edges: [JSON], pageInfo: JSON?, query: Query, parent: Node?, extraQueries: LinkedList<Query>) async throws {
            do {
                for node in edges.compactMap({ $0["node"] as? JSON }) {
                    try await scanNode(node, query: query, parent: parent, extraQueries: extraQueries)
                }

                if let latestCursor = edges.last?["cursor"] as? String,
                   let pageInfo, pageInfo["hasNextPage"] as? Bool == true,
                   let parentId = parent?.id {
                    let newGroup = Group(cloning: self, lastCursor: latestCursor)
                    if let shellRootElement = query.rootElement.asShell(for: newGroup, batchRootId: parentId) as? GQLScanning {
                        let nextPage = Query(from: query, with: shellRootElement)
                        extraQueries.append(nextPage)
                    }
                }

            } catch GQLError.alreadyParsed {
                // exhausted new nodes
            }

            if extraQueries.count > 0 {
                DLog("\(query.logPrefix)(Page in: \(name)) will need further paging: \(extraQueries.count) new queries")
            }
        }

        private func scanList(nodes: [JSON], query: Query, parent: Node?, extraQueries: LinkedList<Query>) async throws {
            do {
                for node in nodes {
                    try await scanNode(node, query: query, parent: parent, extraQueries: extraQueries)
                }
            } catch GQLError.alreadyParsed {
                // exhausted new nodes
            }

            if extraQueries.count > 0 {
                DLog("\(query.logPrefix)(Group: \(name)) will need further paging: \(extraQueries.count) new queries")
            }
        }

        func scan(query: Query, pageData: Any, parent: Node?, extraQueries: LinkedList<Query>) async throws {
            if let hash = pageData as? JSON {
                if let edges = hash["edges"] as? [JSON] {
                    try await scanPage(edges, pageInfo: hash["pageInfo"] as? JSON, query: query, parent: parent, extraQueries: extraQueries)
                } else {
                    do {
                        try await scanNode(hash, query: query, parent: parent, extraQueries: extraQueries)
                    } catch GQLError.alreadyParsed {
                        // not a new node, ignore
                    }
                }

            } else if let nodes = pageData as? [JSON] {
                try await scanList(nodes: nodes, query: query, parent: parent, extraQueries: extraQueries)
            }
        }
    }
}
