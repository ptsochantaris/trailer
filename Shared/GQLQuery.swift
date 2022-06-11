import Dispatch
import Foundation

final class GQLQuery {
    let name: String
    let perNodeBlock: ((GQLNode) async throws -> Void)?

    private let rootElement: GQLScanning
    private let parent: GQLNode?
    private let allowsEmptyResponse: Bool

    init(name: String, rootElement: GQLScanning, parent: GQLNode? = nil, allowsEmptyResponse: Bool = false, perNode: ((GQLNode) async throws -> Void)? = nil) {
        self.rootElement = rootElement
        self.parent = parent
        self.name = name
        self.allowsEmptyResponse = allowsEmptyResponse
        perNodeBlock = perNode
    }

    static func batching(_ name: String, fields: [GQLElement], idList: ContiguousArray<String>, batchSize: Int, perNode: ((GQLNode) async throws -> Void)? = nil) -> [GQLQuery] {
        var list = idList
        var queries = [GQLQuery]()
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

    private static let qlQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 2
        q.qualityOfService = .background
        return q
    }()

    var logPrefix: String {
        "(GQL '\(name)') "
    }

    func run(for url: String, authToken: String, attempt: Int) async throws -> ApiStats? {
        let Q = queryText
        if Settings.dumpAPIResponsesInConsole {
            DLog("\(logPrefix)Fetching: \(Q)")
        }

        let server = URL(string: url)!
        var r = URLRequest(url: server)
        r.httpMethod = "POST"
        r.httpBody = try! JSONEncoder().encode(["query": Q])
        r.setValue("bearer \(authToken)", forHTTPHeaderField: "Authorization")

        Task { @MainActor in
            API.currentOperationName = name
        }

        var apiStats: ApiStats?
        var shouldRetry = false
        do {
            let (info, response) = try await HTTP.getData(for: r)
            guard let json = try JSONSerialization.jsonObject(with: info, options: []) as? [AnyHashable: Any] else {
                throw API.apiError("\(logPrefix)Invalid JSON")
            }

            if Settings.dumpAPIResponsesInConsole {
                DLog("\(logPrefix)API data from %@: %@", url, String(bytes: info, encoding: .utf8))
            }

            apiStats = ApiStats.fromV4(json: json["data"] as? [AnyHashable: Any])
            if let s = apiStats {
                DLog("\(logPrefix)Received page (Cost: \(s.cost), Remaining: \(s.remaining)/\(s.limit) - Node Count: \(s.nodeCount))")
            } else {
                DLog("\(logPrefix)Received page (No stats)")
            }

            let allData = json["data"] as? [AnyHashable: Any]
            guard let data = (parent == nil) ? allData : allData?["node"] as? [AnyHashable: Any] else {
                let code = response.statusCode
                shouldRetry = code == 403 || code == 502 || code == 503 || code == -1001 // pause to retry in case of throttle or ongoing GH deployment or timeout
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
                if extraQueries.isEmpty {
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
            if shouldRetry, attempt > 0 {
                DLog("\(logPrefix) Pausing for retry, attempt \(attempt)")
                try? await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
                return try await run(for: url, authToken: authToken, attempt: attempt - 1)
            } else {
                throw error
            }
        }
    }

    static func runQueries(queries: [GQLQuery], on path: String, token: String) async throws -> ApiStats? {
        try await withThrowingTaskGroup(of: ApiStats?.self, returning: ApiStats?.self) { group in
            for query in queries {
                group.addTask {
                    try await query.run(for: path, authToken: token, attempt: 10)
                }
            }
            return try await group.reduce(nil) { $1 ?? $0 }
        }
    }
}
