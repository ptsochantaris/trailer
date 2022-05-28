import Foundation

final class RestAccess {

    private struct UrlBackOffEntry {
        var nextAttemptAt: Date
        var nextIncrement: TimeInterval
    }
    
    @MainActor
    static func getPagedData(at path: String, from server: ApiServer, startingFrom page: Int = 1, perPage: @escaping ([[AnyHashable: Any]]?, Bool) -> Bool) async -> (Bool, Int) {
        
        if path.isEmpty {
            // handling empty or nil fields as success, since we don't want syncs to fail, we simply have nothing to process
            return (true, -1)
        }
        
        do {
            let p = page > 1 ? "\(path)?page=\(page)&per_page=100" : "\(path)?per_page=100"
            let (data, lastPage, resultCode) = try await getData(in: p, from: server)
            if perPage(data as? [[AnyHashable: Any]], lastPage) || lastPage {
                return (true, resultCode)
            } else {
                return await getPagedData(at: path, from: server, startingFrom: page+1, perPage: perPage)
            }
        } catch {
            return (false, (error as NSError).code)
        }
    }

    @MainActor
    static func getData(in path: String, from server: ApiServer, attemptCount: Int = 0) async throws -> (Any?, Bool, Int) {
        var attemptCount = attemptCount
        API.currentOperationCount += 1
        defer {
            API.currentOperationCount -= 1
        }
        while true {
            do {
                let (code, headers, data) = try await start(call: path, on: server, triggeredByUser: false)
                var lastPage = true
                if let allHeaders = headers {
                    
                    let latestLimits = ApiStats.fromV3(headers: allHeaders)
                    server.updateApiStats(latestLimits)
                    
                    if let linkHeader = allHeaders["Link"] as? String {
                        lastPage = !linkHeader.contains("rel=\"next\"")
                    }
                }
                return (data, lastPage, code)
            } catch {
                let error = error as NSError
                let code = error.code
                let shouldRetry = (code == 502 || code == 503 || code == -1001) // retry in case GH is deploying, or timeout
                if !shouldRetry || attemptCount > 2 {
                    DLog("(%@) Giving up on failed API call to %@", S(server.label), path)
                    throw error
                }
            }
            attemptCount += 1
            DLog("(%@) Will retry failed API call to %@ (attempt #%@)", S(server.label), path, attemptCount)
            try? await Task.sleep(nanoseconds: 3 * NSEC_PER_SEC)
        }
    }
    
    @MainActor
    static func getRawData(at path: String, from server: ApiServer) async throws -> (Any?, Int) {
        if path.isEmpty {
            // handling empty or nil fields as success, since we don't want syncs to fail, we simply have nothing to process
            return (nil, -1)
        }

        let (data, _, resultCode) = try await getData(in: "\(path)?per_page=100", from: server)
        return (data, resultCode)
    }
    
    @MainActor
    static func start(call path: String, on server: ApiServer, triggeredByUser: Bool) async throws -> (Int, [AnyHashable: Any]?, Any?) {
        
        let apiServerLabel: String
        if server.lastSyncSucceeded || triggeredByUser {
            apiServerLabel = S(server.label)
        } else {
            throw API.apiError("Sync has failed, skipping this call")
        }
        
        let expandedPath = path.hasPrefix("/") ? S(server.apiPath).appending(pathComponent: path) : path
        let url = URL(string: expandedPath)!

        var request = URLRequest(url: url)
        var acceptTypes = [String]()
        if API.shouldSyncReactions {
            acceptTypes.append("application/vnd.github.squirrel-girl-preview")
        }
        if (API.shouldSyncReviews || API.shouldSyncReviewAssignments) && (!server.isGitHub) {
            acceptTypes.append("application/vnd.github.black-cat-preview+json")
        }
        acceptTypes.append("application/vnd.github.shadow-cat-preview+json") // draft indicators
        acceptTypes.append("application/vnd.github.v3+json")
        request.setValue(acceptTypes.joined(separator: ", "), forHTTPHeaderField: "Accept")
        if let a = server.authToken {
            request.setValue("token \(a)", forHTTPHeaderField: "Authorization")
        }

        let capturedRequest = request
        do {
            let (data, response) = try await HTTP.getData(for: capturedRequest)
            let headers = response.allHeaderFields
            let code = response.statusCode
            
            DLog("(%@) GET %@ - RESULT: %@", apiServerLabel, expandedPath, code)
            let parsedData = try? JSONSerialization.jsonObject(with: data, options: [])
            
            if Settings.dumpAPIResponsesInConsole {
                DLog("API data from %@: %@", expandedPath, String(bytes: data, encoding: .utf8))
            }
            return (code, headers, parsedData)

        } catch {
            let error = error as NSError
            DLog("(%@) GET %@ - FAILED: (code %@) %@", apiServerLabel, expandedPath, error.code, error.localizedDescription)
            throw error
        }
    }
}
