import Foundation

final class GQLGroup: GQLScanning {

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
        self.lastCursor = nil
	}
    
    init(group: GQLGroup, name: String? = nil, lastCursor: String? = nil) {
        self.name = name ?? group.name
        self.fields = group.fields
        self.pageSize = group.pageSize
        self.onlyLast = group.onlyLast
        self.extraParams = group.extraParams
        self.noPaging = group.noPaging
        self.lastCursor = lastCursor
    }
	
	var queryText: String {
		
		var query = name
		var brackets = [String]()
		
		if pageSize > 0 {
			if onlyLast {
				brackets.append("last: 1")
			} else {
                brackets.append("first: \(pageSize)")
				if let lastCursor = lastCursor {
					brackets.append("after: \"\(lastCursor)\"")
				}
			}
		}
		
		if let e = extraParams {
			for (k, v) in e {
				brackets.append("\(k): \(v)")
			}
		}
		
		if !brackets.isEmpty {
			query += "(" + brackets.joined(separator: ", ") + ")"
		}
		
		let fieldsText = "__typename " + fields.map({$0.queryText}).joined(separator: " ")
		
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
	
	var fragments: [GQLFragment] { fields.reduce([]) { $0 + $1.fragments } }
    
    private static let nodeCallbackLock = NSLock()

    @discardableResult
    private func scanNode(_ node: [AnyHashable: Any], query: GQLQuery, parent: GQLNode?) async -> (extras: [GQLQuery], shouldScanMore: Bool) {
        
        let thisObject: GQLNode?
        
        if let typeName = node["__typename"] as? String, let id = node["id"] as? String {
            let o = GQLNode(id: id, elementType: typeName, jsonPayload: node, parent: parent)
            thisObject = o
            if let pnc = query.perNodeCallback {
                GQLGroup.nodeCallbackLock.lock()
                let keepGoing = await pnc(o)
                GQLGroup.nodeCallbackLock.unlock()
                if !keepGoing {
                    if let parent = parent {
                        DLog("\(query.logPrefix)Don't need further '\(typeName)' items for parent ID '\(parent.id)', got all the updated ones already")
                    } else {
                        DLog("\(query.logPrefix)Don't need further '\(typeName)' items, got all the updated ones already")
                    }
                    return ([], false) // this and later nodes aren't of interest
                }
            }
        } else { // we're a container, not an object, unwrap this level and recurse into it
            thisObject = parent
        }
        
        var extraQueries = [GQLQuery]()
        
        for field in fields {
            if let fragment = field as? GQLFragment {
                extraQueries += await fragment.scan(query: query, pageData: node, parent: thisObject)
                
            } else if let ingestable = field as? GQLScanning, let fieldData = node[field.name] {
                extraQueries += await ingestable.scan(query: query, pageData: fieldData, parent: thisObject)
            }
        }
        
        return (extraQueries, true)
    }
    
    private func scanPage(_ edges: [[AnyHashable: Any]], pageInfo: [AnyHashable: Any]?, query: GQLQuery, parent: GQLNode?, extraQueries: inout [GQLQuery]) async {
        for e in edges {
            if let node = e["node"] as? [AnyHashable : Any] {
                let (extras, canScanMore) = await scanNode(node, query: query, parent: parent)
                if !canScanMore {
                    return
                }
                extraQueries += extras
            }
        }
        if let latestCursor = edges.last?["cursor"] as? String,
            let pageInfo = pageInfo, pageInfo["hasNextPage"] as? Bool == true {
            let newGroup = GQLGroup(group: self, lastCursor: latestCursor)
            let nextPage = GQLQuery(name: query.name, rootElement: newGroup, parent: parent, perNodeCallback: query.perNodeCallback)
            extraQueries.append(nextPage)
        }
    }

	func scan(query: GQLQuery, pageData: Any, parent: GQLNode?) async -> [GQLQuery] {

		var extraQueries = [GQLQuery]()
                
		if let hash = pageData as? [AnyHashable : Any] {
			if let edges = hash["edges"] as? [[AnyHashable : Any]] {
                await scanPage(edges, pageInfo: hash["pageInfo"] as? [AnyHashable : Any], query: query, parent: parent, extraQueries: &extraQueries)
			} else {
                extraQueries += await scanNode(hash, query: query, parent: parent).extras
			}
			
		} else if let nodes = pageData as? [[AnyHashable : Any]] {
            extraQueries = await withTaskGroup(of: [GQLQuery].self) { group in
                for node in nodes {
                    group.addTask { [weak self] in
                        guard let self = self else { return [] }
                        return await self.scanNode(node, query: query, parent: parent).extras
                    }
                }
                return await group.reduce([GQLQuery]()) { partialResult, new in
                    return partialResult + new
                }
            }
		}
		
		if !extraQueries.isEmpty {
			DLog("\(query.logPrefix)\(name) will need further paging")
		}
		return extraQueries
	}
}
