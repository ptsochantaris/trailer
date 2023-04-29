import Foundation

struct GQLFragment: GQLScanning, Hashable {
    let id: UUID
    let name: String
    
    private let elements: [GQLElement]
    private let type: String

    var nodeCost: Int {
        elements.reduce(0) { $0 + $1.nodeCost }
    }
    
    var queryText: String {
        "... \(name)"
    }
    
    func asShell(for element: GQLElement) -> GQLElement? {
        if element.id == id {
            return element
        }
        
        var elementsToKeep = elements.compactMap { $0.asShell(for: element) }
        if elementsToKeep.isEmpty {
            return nil
        }
        if let idField = elements.first(where: { $0.name == GraphQL.idField.name }) {
            elementsToKeep.append(idField)
        }
        return GQLFragment(cloning: self, elements: elementsToKeep)
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

    init(cloning: GQLFragment, elements: [GQLElement]) {
        self.id = cloning.id
        self.name = cloning.name
        self.type = cloning.type
        self.elements = elements
    }

    init(on type: String, @GQLElementsBuilder elements: () -> [GQLElement]) {
        id = UUID()
        name = type.lowercased() + "Fragment"
        self.type = type
        self.elements = elements()
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
