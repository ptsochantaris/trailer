import Foundation

protocol GQLElement {
    var name: String { get }
    var queryText: String { get }
    var fragments: [GQLFragment] { get }
}
