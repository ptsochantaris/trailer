import Foundation

protocol GQLElement {
    var name: String { get }
    var queryText: String { get }
    var fragments: LinkedList<GQLFragment> { get }
    var nodeCost: Int { get }
}
