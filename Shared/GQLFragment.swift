import Foundation

struct GQLFragment: GQLScanning, Hashable {
    let name: String

    private let elements: [GQLElement]
    private let type: String

    var queryText: String {
        "... \(name)"
    }

    var declaration: String {
        "fragment \(name) on \(type) { __typename " + elements.map(\.queryText).joined(separator: " ") + " }"
    }

    var fragments: LinkedList<GQLFragment> {
        let res = LinkedList<GQLFragment>(value: self)
        for element in elements {
            res.append(contentsOf: element.fragments)
        }
        return res
    }

    init(on type: String, elements: [GQLElement]) {
        name = type.lowercased() + "Fragment"
        self.type = type
        self.elements = elements
    }

    func scan(query: GQLQuery, pageData: Any, parent: GQLNode?) async -> LinkedList<GQLQuery> {
        // DLog("\(query.logPrefix)Scanning fragment \(name)")
        guard let hash = pageData as? [AnyHashable: Any] else { return LinkedList<GQLQuery>() }

        let extraQueries = LinkedList<GQLQuery>()
        for element in elements {
            if let element = element as? GQLScanning, let elementData = hash[element.name] {
                let newQueries = await element.scan(query: query, pageData: elementData, parent: parent)
                extraQueries.append(contentsOf: newQueries)
            }
        }
        return extraQueries
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    static func == (lhs: GQLFragment, rhs: GQLFragment) -> Bool {
        lhs.name == rhs.name
    }
}
