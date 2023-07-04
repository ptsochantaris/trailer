import Foundation

extension GraphQL {
    final class Node: Hashable {
        let id: String
        let elementType: String
        let jsonPayload: JSON
        let parent: Node?
        var creationSkipped = false
        var created = false
        var updated = false
        var forcedUpdate = false

        init?(jsonPayload: JSON, parent: Node?) {
            guard let id = jsonPayload["id"] as? String,
                  let elementType = jsonPayload["__typename"] as? String
            else { return nil }
            
            self.id = id
            self.elementType = elementType
            self.jsonPayload = jsonPayload
            self.parent = parent
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            if let parentId = parent?.id {
                hasher.combine(parentId)
            }
        }

        static func == (lhs: Node, rhs: Node) -> Bool {
            (lhs.id == rhs.id) && (lhs.parent?.id == rhs.parent?.id)
        }
    }
}
