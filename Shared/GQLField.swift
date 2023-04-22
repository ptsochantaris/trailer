import Foundation

let emptyList = LinkedList<GQLFragment>()

struct GQLField: GQLElement {
    let name: String
    var queryText: String { name }
    let fragments = emptyList
    let nodeCost = 0
}
