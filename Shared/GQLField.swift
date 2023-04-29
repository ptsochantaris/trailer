import Foundation

let emptyList = LinkedList<GQLFragment>()

struct GQLField: GQLElement {
    let id = UUID()
    let name: String
    var queryText: String { name }
    let fragments = emptyList
    let nodeCost = 0
    
    init(_ name: String) {
        self.name = name
    }
    
    func asShell(for element: GQLElement) -> GQLElement? {
        if element.id == id {
            return element
        } else {
            return nil
        }
    }
}
