import Foundation

protocol GQLElement {
    var id: UUID { get }
    var name: String { get }
    var queryText: String { get }
    var fragments: LinkedList<GraphQL.Fragment> { get }
    var nodeCost: Int { get }

    func asShell(for element: GQLElement) -> GQLElement?
}

extension GraphQL {
    @resultBuilder
    enum GQLElementsBuilder {
        static func buildBlock(_ components: GQLElement...) -> [GQLElement] {
            components
        }

        static func buildBlock(_ components: [GQLElement]...) -> [GQLElement] {
            components.flatMap { $0 }
        }

        static func buildArray(_ components: [GQLElement]) -> [GQLElement] {
            components
        }

        static func buildArray(_ components: [[GQLElement]]) -> [GQLElement] {
            components.flatMap { $0 }
        }

        static func buildOptional(_ component: [GQLElement]?) -> [GQLElement] {
            component ?? []
        }

        static func buildPartialBlock(first: GQLElement) -> [GQLElement] {
            [first]
        }

        static func buildPartialBlock(accumulated: [GQLElement], next: GQLElement) -> [GQLElement] {
            var accumulated = accumulated
            accumulated.append(next)
            return accumulated
        }

        static func buildPartialBlock(first: [GQLElement]) -> [GQLElement] {
            first
        }

        static func buildPartialBlock(accumulated: [GQLElement], next: [GQLElement]) -> [GQLElement] {
            accumulated + next
        }
    }
}
