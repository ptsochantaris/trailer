import Foundation

let emptyList = LinkedList<GQLFragment>()

struct GQLField: GQLElement {
    let name: String
    var queryText: String { name }
    var fragments: LinkedList<GQLFragment> { emptyList }
}
