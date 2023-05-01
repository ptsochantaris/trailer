import Foundation

extension GraphQL {
    static let emptyList = LinkedList<Fragment>()
    
    struct Field: GQLElement {
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
}
