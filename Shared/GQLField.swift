import Foundation

final class GQLField: GQLElement {
    let name: String
    var queryText: String { return name }
    var fragments: [GQLFragment] { return [] }
    
    init(name: String) {
        self.name = name
    }
}
