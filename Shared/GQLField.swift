import Foundation

final class GQLField: GQLElement {
    let name: String
    var queryText: String { name }
    var fragments: [GQLFragment] { [] }

    init(name: String) {
        self.name = name
    }
}
