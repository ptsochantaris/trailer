import Foundation

final class GQLGroup: GQLScanning {

	let name: String
	let fields: [GQLElement]
	private let pageSize: Int
	private let onlyLast: Bool
	private let extraParams: [String: String]?
	private var lastCursor: String?
	
	init(name: String, fields: [GQLElement], extraParams: [String: String]? = nil, pageSize: Int = 0, onlyLast: Bool = false) {
		self.name = name
		self.fields = fields
		self.pageSize = pageSize
		self.onlyLast = onlyLast
		self.extraParams = extraParams
	}
    
    init(group: GQLGroup, name: String? = nil) {
        self.name = name ?? group.name
        self.fields = group.fields
        self.pageSize = group.pageSize
        self.onlyLast = group.onlyLast
        self.extraParams = group.extraParams
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
			query += " { edges { node { " + fieldsText + " } cursor } pageInfo { hasNextPage } }"
		} else {
			query += " { " + fieldsText + " }"
		}
		
		return query
	}
	
	var fragments: [GQLFragment] {
		var res = [GQLFragment]()
		for f in fields {
			res.append(contentsOf: f.fragments)
		}
		return res
	}
	
    private static let nodeCallbackLock = NSLock()
	private func checkFields(query: GQLQuery, hash: [AnyHashable : Any], parent: GQLNode?) -> ([GQLQuery], String?) {

		let thisObject: GQLNode?
        
        var typeToStop: String?
        if let typeName = hash["__typename"] as? String, let id = hash["id"] as? String {
            let o = GQLNode(id: id, elementType: typeName, jsonPayload: hash, parent: parent)
            thisObject = o
            if let c = query.perNodeCallback {
                GQLGroup.nodeCallbackLock.lock()
                if c(o) == false {
                    typeToStop = typeName
                }
                GQLGroup.nodeCallbackLock.unlock()
            }
        } else { // unwrap this level
            thisObject = parent
        }
		
        var extraQueries = [GQLQuery]()
		for field in fields {
			if let fragment = field as? GQLFragment {
				let newQueries = fragment.scan(query: query, pageData: hash, parent: thisObject)
				extraQueries.append(contentsOf: newQueries)
                
			} else if let ingestable = field as? GQLScanning, let fieldData = hash[field.name] {
				let newQueries = ingestable.scan(query: query, pageData: fieldData, parent: thisObject)
				extraQueries.append(contentsOf: newQueries)
			}
		}
        return (extraQueries, typeToStop)
	}
	
	func scan(query: GQLQuery, pageData: Any, parent: GQLNode?) -> [GQLQuery] {

		var extraQueries = [GQLQuery]()

		if let hash = pageData as? [AnyHashable : Any] { // data was a dictionary
			if let edges = hash["edges"] as? [[AnyHashable : Any]] {
				var latestCursor: String?
                var typeToStopSignal: String?
				for e in edges {
                    latestCursor = e["cursor"] as? String
					if let node = e["node"] as? [AnyHashable : Any] {
						let (newQueries, typeToStop) = checkFields(query: query, hash: node, parent: parent)
						extraQueries.append(contentsOf: newQueries)
                        if let typeToStop = typeToStop, node["__typename"] as? String == typeToStop {
                            typeToStopSignal = typeToStop
                        }
                    }
				}
				if let latestCursor = latestCursor, let pageInfo = hash["pageInfo"] as? [AnyHashable : Any], pageInfo["hasNextPage"] as? Bool == true {
                    if let typeToStop = typeToStopSignal {
                        DLog("\(query.logPrefix)Don't need more '\(typeToStop)' items for parent ID '\(parent?.id ?? "<none>")', got all the updated ones already")
                    } else {
                        let newGroup = GQLGroup(group: self)
                        newGroup.lastCursor = latestCursor
                        let nextPage = GQLQuery(name: query.name, rootElement: newGroup, parent: parent, perNodeCallback: query.perNodeCallback)
                        extraQueries.append(nextPage)
                    }
                }

			} else {
				let (newQueries, typeToStop) = checkFields(query: query, hash: hash, parent: parent)
                if !newQueries.isEmpty {
                    if let typeToStop = typeToStop, hash["__typename"] as? String == typeToStop {
                        DLog("\(query.logPrefix)Don't need more '\(typeToStop)' items for parent ID '\(parent?.id ?? "<none>")', got all the updated ones already")
                    } else {
                        extraQueries.append(contentsOf: newQueries)
                    }
                }
			}
			
		} else if let nodes = pageData as? [[AnyHashable : Any]] { // data was an array of dictionaries with no paging info
			for node in nodes {
				let (newQueries, typeToStop) = checkFields(query: query, hash: node, parent: parent)
                if !newQueries.isEmpty {
                    if let typeToStop = typeToStop, node["__typename"] as? String == typeToStop {
                        DLog("\(query.logPrefix)Don't need more '\(typeToStop)' items for parent ID '\(parent?.id ?? "<none>")', got all the updated ones already")
                    } else {
                        extraQueries.append(contentsOf: newQueries)
                    }
                }
			}
		}
		
		if !extraQueries.isEmpty {
			DLog("\(query.logPrefix)\(name) will need further paging")
		}
		return extraQueries
	}
}
