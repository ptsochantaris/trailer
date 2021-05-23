import Foundation

final class GQLFragment: GQLScanning, Hashable {
    
	let name: String

    private let elements: [GQLElement]
    private let type: String

	var queryText: String {
		return "... \(name)"
	}

	var declaration: String {
		return "fragment \(name) on \(type) { __typename " + elements.map({$0.queryText}).joined(separator: " ") + " }"
	}

	var fragments: [GQLFragment] { elements.reduce([self]) { $0 + $1.fragments } }

	init(on type: String, elements: [GQLElement]) {
        self.name = type.lowercased() + "Fragment"
		self.type = type
		self.elements = elements
	}
	
	func scan(query: GQLQuery, pageData: Any, parent: GQLNode?) -> [GQLQuery] {
		//DLog("\(query.logPrefix)Scanning fragment \(name)")
		guard let hash = pageData as? [AnyHashable : Any] else { return [] }

		var extraQueries = [GQLQuery]()
		for element in elements {
			if let element = element as? GQLScanning, let elementData = hash[element.name] {
				let newQueries = element.scan(query: query, pageData: elementData, parent: parent)
				extraQueries.append(contentsOf: newQueries)
			}
		}
		return extraQueries
	}
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
    
    static func == (lhs: GQLFragment, rhs: GQLFragment) -> Bool {
        return lhs.name == rhs.name
    }
}
