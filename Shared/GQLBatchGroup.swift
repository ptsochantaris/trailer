import Foundation

final class GQLBatchGroup: GQLScanning {
	let name = "nodes"

	private var idsToGroups = [String : GQLGroup]()
	private let originalTemplate: GQLGroup
	private let nextCount: Int
    private let batchSize: Int

    init(templateGroup: GQLGroup, idList: [String], startingCount: Int = 0, batchSize: Int) {
        originalTemplate = templateGroup
		var index = startingCount
		for id in idList {
            let t = GQLGroup(group: templateGroup, name: templateGroup.name + "\(index)")
			idsToGroups[id] = t
			index += 1
		}
		nextCount = index
        self.batchSize = batchSize
	}

	var queryText: String {
		if let templateGroup = idsToGroups.values.first {
			return "nodes(ids: [\"" + pageOfIds.joined(separator: "\",\"") + "\"]) { " + templateGroup.fields.map { $0.queryText }.joined(separator: " ") + " }"
		} else {
			return ""
		}
	}

	var fragments: [GQLFragment] {
		var fragments = [GQLFragment]()
		for f in idsToGroups.values {
			let newFragments = f.fragments
			fragments.append(contentsOf: newFragments)
		}
		return fragments
	}

	private var pageOfIds: [String] {
		let k = idsToGroups.keys.sorted()
		let max = min(batchSize, k.count)
		return Array(k[0 ..< max])
	}

	func scan(query: GQLQuery, pageData: Any, parent: GQLNode?) -> [GQLQuery] {
        //DLog("\(query.logPrefix)Scanning batch group \(name)")
		guard let nodes = pageData as? [Any] else { return [] }

		var extraQueries = [GQLQuery]()

		let page = pageOfIds
		let newIds = idsToGroups.keys.filter { !page.contains($0) }
		if !newIds.isEmpty {
			let nextPage = GQLQuery(name: query.name, rootElement: GQLBatchGroup(templateGroup: originalTemplate, idList: newIds, startingCount: nextCount, batchSize: batchSize), parent: parent)
			extraQueries.append(nextPage)
		}

		for n in nodes {
			if let n = n as? [AnyHashable : Any], let id = n["id"] as? String, let group = idsToGroups[id] {
				let newQueries = group.scan(query: query, pageData: n, parent: parent)
				extraQueries.append(contentsOf: newQueries)
			}
		}

		if !extraQueries.isEmpty {
			DLog("\(query.logPrefix)\(name) - Will need further paging")
		}
		return extraQueries
	}
}
