import Foundation

extension GraphQL {
    struct Fragment: GQLScanning, Hashable {
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

        func asShell(for element: GQLElement, batchRootId _: String?) -> GQLElement? {
            if element.id == id {
                return element
            }

            var elementsToKeep = elements.compactMap { $0.asShell(for: element, batchRootId: nil) }
            if elementsToKeep.isEmpty {
                return nil
            }
            if let idField = elements.first(where: { $0.name == idField.name }) {
                elementsToKeep.append(idField)
            }
            return Fragment(cloning: self, elements: elementsToKeep)
        }

        var declaration: String {
            "fragment \(name) on \(type) { __typename " + elements.map(\.queryText).joined(separator: " ") + " }"
        }

        var fragments: LinkedList<Fragment> {
            let res = LinkedList<Fragment>(value: self)
            for element in elements {
                res.append(contentsOf: element.fragments)
            }
            return res
        }

        private init(cloning: Fragment, elements: [GQLElement]) {
            id = cloning.id
            name = cloning.name
            type = cloning.type
            self.elements = elements
        }

        init(on type: String, @GQLElementsBuilder elements: () -> [GQLElement]) {
            id = UUID()
            name = type.lowercased() + "Fragment"
            self.type = type
            self.elements = elements()
        }

        func scan(query: Query, pageData: Any, parent: Node?, extraQueries: LinkedList<Query>) async throws {
            // DLog("\(query.logPrefix)Scanning fragment \(name)")
            guard let hash = pageData as? JSON else { return }

            for element in elements {
                if let element = element as? GQLScanning, let elementData = hash[element.name] {
                    try await element.scan(query: query, pageData: elementData, parent: parent, extraQueries: extraQueries)
                }
            }
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(name)
        }

        static func == (lhs: Fragment, rhs: Fragment) -> Bool {
            lhs.name == rhs.name
        }
    }
}
