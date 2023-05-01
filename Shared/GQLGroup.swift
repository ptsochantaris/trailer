import Foundation

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
            self.extraParams = params
            lastCursor = nil
        }
        
        init(group: Group, name: String? = nil, lastCursor: String? = nil, replacedFields: [GQLElement]? = nil) {
            self.id = group.id
            self.name = name ?? group.name
            fields = replacedFields ?? group.fields
            paging = group.paging
            extraParams = group.extraParams
            self.lastCursor = lastCursor
        }
        
        func asShell(for element: GQLElement) -> GQLElement? {
            if element.id == id {
                return element
            }
            
            let replacementFields = fields.compactMap { $0.asShell(for: element) }
            if replacementFields.isEmpty {
                return nil
            }
            return Group(group: self, replacedFields: replacementFields)
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
            let estimatedBatchSize = (500000 / templateCost).rounded(.down)
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
        
        @discardableResult
        private func scanNode(_ node: [AnyHashable: Any], query: Query, parent: Node?) async throws -> LinkedList<Query> {
            let thisObject: Node?
            
            if let typeName = node["__typename"] as? String, let id = node["id"] as? String {
                let o = Node(id: id, elementType: typeName, jsonPayload: node, parent: parent)
                try await query.perNodeBlock?(o)
                thisObject = o
                
            } else { // we're a container, not an object, unwrap this level and recurse into it
                thisObject = parent
            }
            
            let extraQueries = LinkedList<Query>()
            
            for field in fields {
                if let fragment = field as? Fragment {
                    await extraQueries.append(contentsOf: fragment.scan(query: query, pageData: node, parent: thisObject))
                    
                } else if let ingestable = field as? GQLScanning, let fieldData = node[field.name] {
                    await extraQueries.append(contentsOf: ingestable.scan(query: query, pageData: fieldData, parent: thisObject))
                }
            }
            
            return extraQueries
        }
        
        private func scanPage(_ edges: [[AnyHashable: Any]], pageInfo: [AnyHashable: Any]?, query: Query, parent: Node?) async -> LinkedList<Query> {
            let extraQueries = LinkedList<Query>()
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
                let newGroup = Group(group: self, lastCursor: latestCursor)
                if let shellRootElement = query.rootElement.asShell(for: newGroup) as? GQLScanning {
                    let nextPage = Query(from: query, with: shellRootElement)
                    extraQueries.append(nextPage)
                }
            }
            return extraQueries
        }
        
        func scan(query: Query, pageData: Any, parent: Node?) async -> LinkedList<Query> {
            var extraQueries = LinkedList<Query>()
            
            if let hash = pageData as? [AnyHashable: Any] {
                if let edges = hash["edges"] as? [[AnyHashable: Any]] {
                    extraQueries = await scanPage(edges, pageInfo: hash["pageInfo"] as? [AnyHashable: Any], query: query, parent: parent)
                } else {
                    extraQueries = await (try? scanNode(hash, query: query, parent: parent)) ?? LinkedList<Query>()
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
}
