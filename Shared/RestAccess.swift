import Foundation
import TrailerJson

// Main-actor isolated by default. This type holds no state of its own, so it previously
// sat on a private global actor that protected nothing — while forcing every ApiServer
// managed object to cross an actor boundary to reach it. The objects belong to a
// main-queue context, so orchestrating from the main actor is what makes the property
// reads in `start(call:on:...)` correct. Nothing here blocks the main thread: awaiting
// HTTP.getJsonData suspends, and the request itself runs on URLSession's own threads.
enum RestAccess {
    static func getPagedData(at path: String, from server: ApiServer, startingFrom page: Int = 1, perPage: @MainActor @escaping ([TypedJson.Entry]?, Bool) async -> Bool) async -> DataResult {
        if path.isEmpty {
            // handling empty or nil fields as success, since we don't want syncs to fail, we simply have nothing to process
            return .success(headers: [:], data: Data())
        }

        do {
            let p = page > 1 ? "\(path)?page=\(page)&per_page=100" : "\(path)?per_page=100"
            let (data, lastPage, result) = try await getData(in: p, from: server)
            if await perPage(data?.potentialArray, lastPage) || lastPage {
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
        if let data, let userName = data.potentialString(named: "login"), let userId = data.potentialInt(named: "id") {
            if userName.isEmpty || userId <= 0 {
                throw ApiError.noUserRecordFound
            }
        }
    }

    static func getData(in path: String, from server: ApiServer) async throws -> (TypedJson.Entry?, Bool, DataResult) {
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
                let serverId = server.objectID
                await serverMoc.perform {
                    if let taskServer = serverMoc.registeredObject(for: serverId) as? ApiServer {
                        let latestLimits = ApiStats.fromV3(headers: allHeaders)
                        taskServer.updateApiStats(latestLimits)
                    }
                }
            }

            if let linkHeader = allHeaders["Link"] {
                lastPage = !linkHeader.contains("rel=\"next\"")
            }
        }
        return (data, lastPage, result)
    }

    static func getRawData(at path: String, from server: ApiServer) async throws -> (TypedJson.Entry?, DataResult) {
        if path.isEmpty {
            // handling empty or nil fields as success, since we don't want syncs to fail, we simply have nothing to process
            return (nil, .success(headers: [:], data: Data()))
        }

        let (data, _, result) = try await getData(in: "\(path)?per_page=100", from: server)
        return (data, result)
    }

    static func start(call path: String, on server: ApiServer, triggeredByUser: Bool, attempts: Int = 5) async throws -> (TypedJson.Entry?, DataResult) {
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
            await Logging.shared.log("(\(apiServerLabel) GET \(expandedPath) - RESULT: \(output.result.logValue)")
            return (output.json, output.result)

        } catch {
            let error = error as NSError
            await Logging.shared.log("(\(apiServerLabel) GET \(expandedPath) - FAILED: (code \(error.code) \(error.localizedDescription)")
            throw error
        }
    }
}
