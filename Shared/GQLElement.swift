import Foundation

protocol GQLElement {
    var id: UUID { get }
    var name: String { get }
    var queryText: String { get }
    var fragments: LinkedList<GQLFragment> { get }
    var nodeCost: Int { get }
    
    func asShell(for element: GQLElement) -> GQLElement?
}
