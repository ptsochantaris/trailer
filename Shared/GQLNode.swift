import Foundation

extension GraphQL {
    final class Node: Hashable {
        let id: String
        let elementType: String
        let jsonPayload: [AnyHashable: Any]
        let parent: Node?
        var creationSkipped = false
        var created = false
        var updated = false
        var forcedUpdate = false
        
        init(id: String, elementType: String, jsonPayload: [AnyHashable: Any], parent: Node?) {
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
