import Foundation

protocol GQLScanning: GQLElement {
    func scan(query: GraphQL.Query, pageData: Any, parent: GraphQL.Node?) async -> LinkedList<GraphQL.Query>
}
