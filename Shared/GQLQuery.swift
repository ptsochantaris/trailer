import AsyncHTTPClient
import Foundation
import NIOCore

extension GraphQL {
    struct Query {
        let name: String
        let perNodeBlock: PerNodeBlock?
        let rootElement: GQLScanning

        private let parent: Node?
        private let allowsEmptyResponse: Bool

        init(name: String, rootElement: GQLScanning, parent: Node? = nil, allowsEmptyResponse: Bool = false, perNode: PerNodeBlock? = nil) {
            self.rootElement = rootElement
            self.parent = parent
            self.name = name
            self.allowsEmptyResponse = allowsEmptyResponse
            perNodeBlock = perNode
        }

        init(from query: Query, with newRootElement: GQLScanning) {
            rootElement = newRootElement
            parent = query.parent
            name = query.name
            allowsEmptyResponse = query.allowsEmptyResponse
            perNodeBlock = query.perNodeBlock
        }

        static func batching(_ name: String, idList: [String], perNode: PerNodeBlock? = nil, @GQLElementsBuilder fields: () -> [GQLElement]) -> LinkedList<Query> {
            var list = ArraySlice(idList)
            let template = Group("items", fields: fields)
            let batchLimit = template.recommendedLimit
            let queries = LinkedList<Query>()

            while !list.isEmpty {
                let chunk = Array(list.prefix(batchLimit))
                let batchGroup = BatchGroup(templateGroup: template, idList: chunk)
                let query = Query(name: name, rootElement: batchGroup, perNode: perNode)
                queries.append(query)
                list = list.dropFirst(batchLimit)
            }
            return queries
        }

        private var rootQueryText: String {
            if let parent {
                return "node(id: \"\(parent.id)\") { ... on \(parent.elementType) { " + rootElement.queryText + " } }"
            } else {
                return rootElement.queryText
            }
        }

        private var fragmentQueryText: String {
            let fragments = Set(rootElement.fragments)
            return fragments.map(\.declaration).joined(separator: " ")
        }

        private var queryText: String {
            fragmentQueryText + " { " + rootQueryText + " rateLimit { limit cost remaining resetAt nodeCount } }"
        }

        var logPrefix: String {
            "(GQL '\(name)') "
        }

        private static let gateKeeper = Gate(tickets: 2)

        private static func fetchData(for request: HTTPClientRequest, attempts: Int) async throws -> Any {
            await gateKeeper.takeTicket()
            defer {
                gateKeeper.relaxedReturnTicket()
            }
            return try await HTTP.getJsonData(for: request, attempts: attempts, checkCache: false).json
        }

        func run(for url: String, authToken: String, attempts: Int = 5) async throws -> ApiStats? {
            let Q = queryText
            if Settings.dumpAPIResponsesInConsole {
                DLog("\(logPrefix)Fetching: \(Q)")
            }

            var request = HTTPClientRequest(url: url)
            request.method = .POST
            let data = try! JSONEncoder().encode(["query": Q])
            request.body = .bytes(ByteBuffer(bytes: data))
            request.headers.add(name: "Authorization", value: "bearer \(authToken)")

            Task { @MainActor in
                API.currentOperationName = name
            }

            var apiStats: ApiStats?

            do {
                let json = try await Query.fetchData(for: request, attempts: attempts)
                guard let json = json as? JSON else {
                    throw API.apiError("\(logPrefix)Retuned data is not JSON")
                }

                apiStats = ApiStats.fromV4(json: json["data"] as? JSON)
                let expectedNodeCost = rootElement.nodeCost
                if let apiStats {
                    DLog("\(logPrefix)Received page (Cost: \(apiStats.cost), Remaining: \(apiStats.remaining)/\(apiStats.limit) - Expected Count: \(expectedNodeCost) - Returned Count: \(apiStats.nodeCount))")
                    if expectedNodeCost != apiStats.nodeCount {
                        DLog("Warning: Mismatched expected and received node count!")
                    }
                } else {
                    DLog("\(logPrefix)Received page (No stats) - Expected Count: \(expectedNodeCost)")
                }

                let allData = json["data"] as? JSON
                guard let data = (parent == nil) ? allData : allData?["node"] as? JSON else {
                    if let errors = json["errors"] as? [JSON] {
                        let msg = errors.first?["message"] as? String ?? "Unspecified server error: \(json)"
                        throw API.apiError(msg)
                    } else {
                        let msg = json["message"] as? String ?? "Unspecified server error: \(json)"
                        throw API.apiError("\(logPrefix)" + msg)
                    }
                }

                guard let topData = data[rootElement.name] else {
                    if allowsEmptyResponse {
                        return apiStats
                    } else {
                        throw API.apiError("\(logPrefix)No data in JSON")
                    }
                }

                DLog("\(logPrefix)Scanning result")

                let extraQueries = await rootElement.scan(query: self, pageData: topData, parent: parent)
                if extraQueries.count == 0 {
                    DLog("\(logPrefix)Parsed all pages")
                    return apiStats
                } else {
                    DLog("\(logPrefix)Needs more page data (\(extraQueries.count) queries)")
                    return try await Query.runQueries(queries: extraQueries, on: url, token: authToken)
                }

            } catch {
                DLog("\(logPrefix)Error: \(error.localizedDescription)")
                throw error
            }
        }

        static func runQueries(queries: LinkedList<Query>, on path: String, token: String) async throws -> ApiStats? {
            try await withThrowingTaskGroup(of: ApiStats?.self, returning: ApiStats?.self) { group in
                for query in queries {
                    group.addTask { @MainActor in
                        if let stats = try await query.run(for: path, authToken: token) {
                            return stats
                        }
                        return nil
                    }
                }
                var mostRecentNonNilStats: ApiStats?
                for try await stats in group where stats != nil {
                    mostRecentNonNilStats = stats
                }
                return mostRecentNonNilStats
            }
        }
    }
}
