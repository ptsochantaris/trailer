import AsyncHTTPClient
import Foundation
import NIOCore

struct GQLQuery {
    let name: String
    let perNodeBlock: PerNodeBlock?

    private let rootElement: GQLScanning
    private let parent: GQLNode?
    private let allowsEmptyResponse: Bool

    init(name: String, rootElement: GQLScanning, parent: GQLNode? = nil, allowsEmptyResponse: Bool = false, perNode: PerNodeBlock? = nil) {
        self.rootElement = rootElement
        self.parent = parent
        self.name = name
        self.allowsEmptyResponse = allowsEmptyResponse
        perNodeBlock = perNode
    }

    static func batching(_ name: String, fields: [GQLElement], idList: [String], batchSize: Int, perNode: PerNodeBlock? = nil) -> LinkedList<GQLQuery> {
        var list = idList
        let queries = LinkedList<GQLQuery>()
        while !list.isEmpty {
            let segment = list.prefix(batchSize)
            list.removeFirst(segment.count)

            let batchGroup = GQLBatchGroup(templateGroup: GQLGroup(name: "items", fields: fields), idList: Array(segment), batchSize: batchSize)
            let query = GQLQuery(name: name, rootElement: batchGroup, perNode: perNode)
            queries.append(query)
        }
        return queries
    }

    private var rootQueryText: String {
        if let parentItem = parent {
            return "node(id: \"\(parentItem.id)\") { ... on \(parentItem.elementType) { " + rootElement.queryText + " } }"
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

    func run(for url: String, authToken: String, attempts: Int = 5) async throws -> ApiStats? {
        let Q = queryText
        if Settings.dumpAPIResponsesInConsole {
            DLog("\(logPrefix)Fetching: \(Q)")
        }

        var r = HTTPClientRequest(url: url)
        r.method = .POST
        let data = try! JSONEncoder().encode(["query": Q])
        r.body = .bytes(ByteBuffer(bytes: data))
        r.headers.add(name: "Authorization", value: "bearer \(authToken)")

        Task { @MainActor in
            API.currentOperationName = name
        }

        var apiStats: ApiStats?
        do {
            let json = try await HTTP.getJsonData(for: r, attempts: attempts, checkCache: false).json
            guard let json = json as? [AnyHashable: Any] else {
                throw API.apiError("\(logPrefix)Invalid JSON")
            }

            apiStats = ApiStats.fromV4(json: json["data"] as? [AnyHashable: Any])
            let expectedNodeCost = self.rootElement.nodeCost
            if let apiStats {
                DLog("\(logPrefix)Received page (Cost: \(apiStats.cost), Remaining: \(apiStats.remaining)/\(apiStats.limit) - Expected Count: \(expectedNodeCost) - Returned Count: \(apiStats.nodeCount))")
                if expectedNodeCost != apiStats.nodeCount {
                    DLog("Warning: Mismatched expected and received node count!")
                }
            } else {
                DLog("\(logPrefix)Received page (No stats) - Expected Count: \(expectedNodeCost)")
            }

            let allData = json["data"] as? [AnyHashable: Any]
            guard let data = (parent == nil) ? allData : allData?["node"] as? [AnyHashable: Any] else {
                if let errors = json["errors"] as? [[AnyHashable: Any]] {
                    let msg = errors.first?["message"] as? String ?? "Unspecified server error: \(json)"
                    throw API.apiError(msg)
                } else {
                    let msg = json["message"] as? String ?? "Unspecified server error: \(json)"
                    throw API.apiError("\(logPrefix)" + msg)
                }
            }

            let r = rootElement
            guard let topData = data[r.name] else {
                if allowsEmptyResponse {
                    return apiStats
                } else {
                    throw API.apiError("\(logPrefix)No data in JSON")
                }
            }

            do {
                let extraQueries = await r.scan(query: self, pageData: topData, parent: parent)
                if extraQueries.count == 0 {
                    DLog("\(logPrefix)Parsed all pages")
                } else {
                    DLog("\(logPrefix)Needs more page data (\(extraQueries.count) queries)")
                    return try await GQLQuery.runQueries(queries: extraQueries, on: url, token: authToken)
                }
            } catch {
                DLog("\(logPrefix)No more page data needed: \(error.localizedDescription)")
            }
            return apiStats

        } catch {
            DLog("\(logPrefix) Error: \(error.localizedDescription)")
            throw error
        }
    }

    static func runQueries(queries: LinkedList<GQLQuery>, on path: String, token: String) async throws -> ApiStats? {
        try await withThrowingTaskGroup(of: ApiStats?.self, returning: ApiStats?.self) { group in
            let gateKeeper = Gate(tickets: 3)

            for query in queries {
                group.addTask { @MainActor in
                    await gateKeeper.takeTicket()
                    defer {
                        gateKeeper.relaxedReturnTicket()
                    }
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
