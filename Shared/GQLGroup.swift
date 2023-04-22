import Foundation

struct GQLGroup: GQLScanning {
    let name: String
    let fields: [GQLElement]
    private let pageSize: Int
    private let onlyLast: Bool
    private let noPaging: Bool
    private let extraParams: [String: String]?
    private let lastCursor: String?

    init(name: String, fields: [GQLElement], extraParams: [String: String]? = nil, pageSize: Int = 0, onlyLast: Bool = false, noPaging: Bool = false) {
        self.name = name
        self.fields = fields
        self.pageSize = pageSize
        self.onlyLast = onlyLast
        self.noPaging = noPaging || onlyLast
        self.extraParams = extraParams
        lastCursor = nil
    }

    init(group: GQLGroup, name: String? = nil, lastCursor: String? = nil) {
        self.name = name ?? group.name
        fields = group.fields
        pageSize = group.pageSize
        onlyLast = group.onlyLast
        extraParams = group.extraParams
        noPaging = group.noPaging
        self.lastCursor = lastCursor
    }
    
    var nodeCost: Int {
        let fieldCost = fields.reduce(0) { $0 + $1.nodeCost }
        if pageSize == 0 {
            return fieldCost
        }
        let count = onlyLast ? 1 : pageSize
        return count + fieldCost * count
    }
    
    var queryText: String {
        var query = name
        let brackets = LinkedList<String>()

        if pageSize > 0 {
            if onlyLast {
                brackets.append("last: 1")
            } else {
                brackets.append("first: \(pageSize)")
                if let lastCursor {
                    brackets.append("after: \"\(lastCursor)\"")
                }
            }
        }

        if let e = extraParams {
            for (k, v) in e {
                brackets.append("\(k): \(v)")
            }
        }

        if brackets.count > 0 {
            query += "(" + brackets.joined(separator: ", ") + ")"
        }

        let fieldsText = "__typename " + fields.map(\.queryText).joined(separator: " ")

        if pageSize > 0 {
            if noPaging {
                query += " { edges { node { " + fieldsText + " } } }"
            } else {
                query += " { edges { node { " + fieldsText + " } cursor } pageInfo { hasNextPage } }"
            }
        } else {
            query += " { " + fieldsText + " }"
        }

        return query
    }

    var fragments: LinkedList<GQLFragment> {
        let res = LinkedList<GQLFragment>()
        for field in fields {
            res.append(contentsOf: field.fragments)
        }
        return res
    }

    @discardableResult
    private func scanNode(_ node: [AnyHashable: Any], query: GQLQuery, parent: GQLNode?) async throws -> LinkedList<GQLQuery> {
        let thisObject: GQLNode?

        if let typeName = node["__typename"] as? String, let id = node["id"] as? String {
            let o = GQLNode(id: id, elementType: typeName, jsonPayload: node, parent: parent)
            try await query.perNodeBlock?(o)
            thisObject = o

        } else { // we're a container, not an object, unwrap this level and recurse into it
            thisObject = parent
        }

        let extraQueries = LinkedList<GQLQuery>()

        for field in fields {
            if let fragment = field as? GQLFragment {
                await extraQueries.append(contentsOf: fragment.scan(query: query, pageData: node, parent: thisObject))

            } else if let ingestable = field as? GQLScanning, let fieldData = node[field.name] {
                await extraQueries.append(contentsOf: ingestable.scan(query: query, pageData: fieldData, parent: thisObject))
            }
        }

        return extraQueries
    }

    private func scanPage(_ edges: [[AnyHashable: Any]], pageInfo: [AnyHashable: Any]?, query: GQLQuery, parent: GQLNode?) async -> LinkedList<GQLQuery> {
        let extraQueries = LinkedList<GQLQuery>()
        var stop = false
        for e in edges {
            if let node = e["node"] as? [AnyHashable: Any] {
                do {
                    try await extraQueries.append(contentsOf: scanNode(node, query: query, parent: parent))
                } catch {
                    stop = true
                    break
                }
            }
        }
        if !stop,
           let latestCursor = edges.last?["cursor"] as? String,
           let pageInfo, pageInfo["hasNextPage"] as? Bool == true {
            let newGroup = GQLGroup(group: self, lastCursor: latestCursor)
            let nextPage = GQLQuery(name: query.name, rootElement: newGroup, parent: parent, perNode: query.perNodeBlock)
            extraQueries.append(nextPage)
        }
        return extraQueries
    }

    func scan(query: GQLQuery, pageData: Any, parent: GQLNode?) async -> LinkedList<GQLQuery> {
        var extraQueries = LinkedList<GQLQuery>()

        if let hash = pageData as? [AnyHashable: Any] {
            if let edges = hash["edges"] as? [[AnyHashable: Any]] {
                extraQueries = await scanPage(edges, pageInfo: hash["pageInfo"] as? [AnyHashable: Any], query: query, parent: parent)
            } else {
                extraQueries = await (try? scanNode(hash, query: query, parent: parent)) ?? LinkedList<GQLQuery>()
            }

        } else if let nodes = pageData as? [[AnyHashable: Any]] {
            for node in nodes {
                do {
                    try await extraQueries.append(contentsOf: scanNode(node, query: query, parent: parent))
                } catch {
                    break
                }
            }
        }

        if extraQueries.count > 0 {
            DLog("\(query.logPrefix)(Group: \(name)) will need further paging")
        }
        return extraQueries
    }
}
