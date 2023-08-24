import Foundation

@MainActor
enum RestAccess {
    private struct UrlBackOffEntry {
        var nextAttemptAt: Date
        var nextIncrement: TimeInterval
    }

    static func getPagedData(at path: String, from server: ApiServer, startingFrom page: Int = 1, perPage: @MainActor @escaping ([JSON]?, Bool) async -> Bool) async -> DataResult {
        if path.isEmpty {
            // handling empty or nil fields as success, since we don't want syncs to fail, we simply have nothing to process
            return .success(headers: [:], data: Data())
        }

        do {
            let p = page > 1 ? "\(path)?page=\(page)&per_page=100" : "\(path)?per_page=100"
            let (data, lastPage, result) = try await getData(in: p, from: server)
            if await perPage(data as? [JSON], lastPage) || lastPage {
                return result
            } else {
                return await getPagedData(at: path, from: server, startingFrom: page + 1, perPage: perPage)
            }
        } catch {
            return .failed(code: 0)
        }
    }

    static func testApi(to apiServer: ApiServer) async throws {
        let (data, _) = try await start(call: "/user", on: apiServer, triggeredByUser: true, attempts: 1)
        if let d = data as? JSON, let userName = d["login"] as? String, let userId = d["id"] as? Int {
            if userName.isEmpty || userId <= 0 {
                throw ApiError.noUserRecordFound
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

        let (data, result) = try await start(call: path, on: server, triggeredByUser: false)
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

            if let linkHeader = allHeaders["Link"] as? String {
                lastPage = !linkHeader.contains("rel=\"next\"")
            }
        }
        return (data, lastPage, result)
    }

    static func getRawData(at path: String, from server: ApiServer) async throws -> (Any?, DataResult) {
        if path.isEmpty {
            // handling empty or nil fields as success, since we don't want syncs to fail, we simply have nothing to process
            return (nil, .success(headers: [:], data: Data()))
        }

        let (data, _, result) = try await getData(in: "\(path)?per_page=100", from: server)
        return (data, result)
    }

    static func start(call path: String, on server: ApiServer, triggeredByUser: Bool, attempts: Int = 5) async throws -> (Any?, DataResult) {
        let apiServerLabel: String
        if server.lastSyncSucceeded || triggeredByUser {
            apiServerLabel = server.label.orEmpty
        } else {
            throw ApiError.cancelled
        }

        let expandedPath = path.hasPrefix("/") ? server.apiPath.orEmpty.appending(pathComponent: path) : path

        guard let url = URL(string: expandedPath) else {
            throw ApiError.invalidUrl(expandedPath)
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.squirrel-girl-preview, application/vnd.github.black-cat-preview+json, application/vnd.github.shadow-cat-preview+json, application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        if let a = server.authToken {
            request.setValue("token \(a)", forHTTPHeaderField: "Authorization")
        }
        if Settings.V4IdMigrationPhase.wantsNewIds {
            request.setValue("1", forHTTPHeaderField: "X-Github-Next-Global-ID")
        }

        do {
            let output = try await HTTP.getJsonData(for: request, attempts: attempts)
            Logging.log("(\(apiServerLabel) GET \(expandedPath) - RESULT: \(output.result.logValue)")
            return output

        } catch {
            let error = error as NSError
            Logging.log("(\(apiServerLabel) GET \(expandedPath) - FAILED: (code \(error.code) \(error.localizedDescription)")
            throw error
        }
    }
}
