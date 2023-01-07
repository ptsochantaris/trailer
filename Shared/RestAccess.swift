import AsyncHTTPClient
import Foundation

@MainActor
enum RestAccess {
    private struct UrlBackOffEntry {
        var nextAttemptAt: Date
        var nextIncrement: TimeInterval
    }

    static func getPagedData(at path: String, from server: ApiServer, startingFrom page: Int = 1, perPage: @MainActor @escaping ([[AnyHashable: Any]]?, Bool) async -> Bool) async -> DataResult {
        if path.isEmpty {
            // handling empty or nil fields as success, since we don't want syncs to fail, we simply have nothing to process
            return .success(headers: [:], cachedIn: nil)
        }

        do {
            let p = page > 1 ? "\(path)?page=\(page)&per_page=100" : "\(path)?per_page=100"
            let (data, lastPage, result) = try await getData(in: p, from: server)
            if await perPage(data as? [[AnyHashable: Any]], lastPage) || lastPage {
                return result
            } else {
                return await getPagedData(at: path, from: server, startingFrom: page + 1, perPage: perPage)
            }
        } catch {
            return .failed(code: 0)
        }
    }

    static func testApi(to apiServer: ApiServer) async throws {
        let (_, data) = try await start(call: "/user", on: apiServer, triggeredByUser: true, attempts: 1)
        if let d = data as? [AnyHashable: Any], let userName = d["login"] as? String, let userId = d["id"] as? Int64 {
            if userName.isEmpty || userId <= 0 {
                let localError = API.apiError("Could not read a valid user record from this endpoint")
                throw localError
            }
        }
    }

    static func getData(in path: String, from server: ApiServer) async throws -> (Any?, Bool, DataResult) {
        Task { @MainActor in
            API.currentOperationCount += 1
        }
        defer {
            Task { @MainActor in
                API.currentOperationCount -= 1
            }
        }

        let (result, data) = try await start(call: path, on: server, triggeredByUser: false)
        var lastPage = true
        if case let .success(allHeaders, _) = result {
            if let serverMoc = server.managedObjectContext {
                #if os(iOS)
                    Task {
                        await serverMoc.perform {
                            let latestLimits = ApiStats.fromV3(headers: allHeaders)
                            server.updateApiStats(latestLimits)
                        }
                    }
                #else
                    serverMoc.perform {
                        let latestLimits = ApiStats.fromV3(headers: allHeaders)
                        server.updateApiStats(latestLimits)
                    }
                #endif
            }

            if let linkHeader = allHeaders["Link"].first {
                lastPage = !linkHeader.contains("rel=\"next\"")
            }
        }
        return (data, lastPage, result)
    }

    static func getRawData(at path: String, from server: ApiServer) async throws -> (Any?, DataResult) {
        if path.isEmpty {
            // handling empty or nil fields as success, since we don't want syncs to fail, we simply have nothing to process
            return (nil, .success(headers: [:], cachedIn: nil))
        }

        let (data, _, result) = try await getData(in: "\(path)?per_page=100", from: server)
        return (data, result)
    }

    static func start(call path: String, on server: ApiServer, triggeredByUser: Bool, attempts: Int = 5) async throws -> (DataResult, Any?) {
        let apiServerLabel: String
        if server.lastSyncSucceeded || triggeredByUser {
            apiServerLabel = S(server.label)
        } else {
            throw API.apiError("Sync has failed, skipping this call")
        }

        let expandedPath = path.hasPrefix("/") ? S(server.apiPath).appending(pathComponent: path) : path

        var request = HTTPClientRequest(url: expandedPath)
        var acceptTypes = [String]()
        if API.shouldSyncReactions {
            acceptTypes.append("application/vnd.github.squirrel-girl-preview")
        }
        if API.shouldSyncReviews || API.shouldSyncReviewAssignments, !server.isGitHub {
            acceptTypes.append("application/vnd.github.black-cat-preview+json")
        }
        acceptTypes.append("application/vnd.github.shadow-cat-preview+json") // draft indicators
        acceptTypes.append("application/vnd.github.v3+json")
        request.headers.add(name: "Accept", value: acceptTypes.joined(separator: ", "))
        if let a = server.authToken {
            request.headers.add(name: "Authorization", value: "token \(a)")
        }

        do {
            let (parsedData, result) = try await HTTP.getJsonData(for: request, attempts: attempts, checkCache: true)
            DLog("(%@) GET %@ - RESULT: %@", apiServerLabel, expandedPath, result.logValue)
            return (result, parsedData)

        } catch {
            let error = error as NSError
            DLog("(%@) GET %@ - FAILED: (code %@) %@", apiServerLabel, expandedPath, error.code, error.localizedDescription)
            throw error
        }
    }
}
