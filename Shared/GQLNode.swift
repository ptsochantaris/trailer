import Foundation

final class GQLNode: Hashable {
    let id: String
    let elementType: String
    let jsonPayload: [AnyHashable: Any]
    let parent: GQLNode?
    var creationSkipped = false
    var created = false
    var updated = false

    init(id: String, elementType: String, jsonPayload: [AnyHashable: Any], parent: GQLNode?) {
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

    static func == (lhs: GQLNode, rhs: GQLNode) -> Bool {
        (lhs.id == rhs.id) && (lhs.parent?.id == rhs.parent?.id)
    }
}
