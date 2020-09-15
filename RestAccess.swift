import Foundation

final class RestAccess {

    typealias ApiCompletion = (_ code: Int64?, _ headers: [AnyHashable : Any]?, _ data: Any?, _ error: Error?, _ shouldRetry: Bool) -> Void

    private struct UrlBackOffEntry {
        var nextAttemptAt: Date
        var nextIncrement: TimeInterval
    }
    
    static func getPagedData(
        at path: String,
        from server: ApiServer,
        startingFrom page: Int = 1,
        perPageCallback: @escaping (_ data: [[AnyHashable : Any]]?, _ lastPage: Bool) -> Bool,
        finalCallback: @escaping (_ success: Bool, _ resultCode: Int64) -> Void) {

        if path.isEmpty {
            // handling empty or nil fields as success, since we don't want syncs to fail, we simply have nothing to process
            finalCallback(true, -1)
            return
        }

        let p = page > 1 ? "\(path)?page=\(page)&per_page=100" : "\(path)?per_page=100"
        getData(in: p, from: server) { data, lastPage, resultCode in

            if let d = data as? [[AnyHashable : Any]] {
                if perPageCallback(d, lastPage) || lastPage {
                    finalCallback(true, resultCode)
                } else {
                    getPagedData(at: path, from: server, startingFrom: page+1, perPageCallback: perPageCallback, finalCallback: finalCallback)
                }
            } else {
                finalCallback(false, resultCode)
            }
        }
    }

    static func getData(
        in path: String,
        from server: ApiServer,
        attemptCount: Int = 0,
        callback: @escaping (_ data: Any?, _ lastPage: Bool, _ resultCode: Int64) -> Void) {

        start(call: path, on: server, triggeredByUser: false) { code, headers, data, error, shouldRetry in

            if error == nil {
                var lastPage = true
                if let allHeaders = headers {

                    let latestLimits = ApiStats.fromV3(headers: allHeaders)
                    server.updateApiStats(latestLimits)

                    if let linkHeader = allHeaders["Link"] as? String {
                        lastPage = !linkHeader.contains("rel=\"next\"")
                    }
                }
                callback(data, lastPage, code ?? 0)
            } else {
                if shouldRetry && attemptCount < 3 { // timeout, truncation, connection issue, etc
                    let nextAttemptCount = attemptCount+1
                    DLog("(%@) Will retry failed API call to %@ (attempt #%@)", S(server.label), path, nextAttemptCount)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        getData(in: path, from: server, attemptCount: nextAttemptCount, callback: callback)
                    }
                } else {
                    if shouldRetry {
                        DLog("(%@) Giving up on failed API call to %@", S(server.label), path)
                    }
                    callback(nil, false, code ?? 0)
                }
            }
        }
    }
    
    static func getRawData(
        at path: String,
        from server: ApiServer,
        callback: @escaping (_ data: Any?, _ resultCode: Int64) -> Void) {

        if path.isEmpty {
            // handling empty or nil fields as success, since we don't want syncs to fail, we simply have nothing to process
            callback(nil, -1)
            return
        }

        getData(in: "\(path)?per_page=100", from: server) { data, lastPage, resultCode in
            callback(data, resultCode)
        }
    }
    
    private static let backOffIncrement: TimeInterval = 120
    private static var badLinks = [String : UrlBackOffEntry]()
    
    static func clearAllBadLinks() {
        badLinks.removeAll(keepingCapacity: false)
    }

    private static let restQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 2
        q.qualityOfService = .background
        return q
    }()

    static func start(call path: String, on server: ApiServer, triggeredByUser: Bool, completion: @escaping ApiCompletion) {
        
        let apiServerLabel: String
        if server.lastSyncSucceeded || triggeredByUser {
            apiServerLabel = S(server.label)
        } else {
            DispatchQueue.main.async {
                let e = API.apiError("Sync has failed, skipping this call")
                completion(nil, nil, nil, e, false)
            }
            return
        }
        
        if triggeredByUser {
            clearAllBadLinks()
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

        ////////////////////////// preempt with error backoff algorithm
        let existingBackOff = badLinks[expandedPath]
        if let eb = existingBackOff {
            if eb.nextAttemptAt.timeIntervalSinceNow > 0 {
                // report failure and return
                DLog("(%@) Preempted fetch to previously broken link %@, won't actually access this URL until %@", apiServerLabel, expandedPath, eb.nextAttemptAt)
                DispatchQueue.main.async {
                    let e = API.apiError("Preempted fetch because of throttling")
                    completion(nil, nil, nil, e, false)
                }
                return
            }
            else {
                badLinks.removeValue(forKey: expandedPath)
            }
        }

        let task = API.task(for: request) { data, res, e in

            let response = res as? HTTPURLResponse
            let error: Error?
            let shouldRetry: Bool
            var parsedData: Any?
            let code = Int64(response?.statusCode ?? 0)
            let headers = response?.allHeaderFields

            if code > 299 {
                error = API.apiError("Server responded with error \(code)")
                shouldRetry = (code == 502 || code == 503) // retry in case GH is deploying
            } else if code == 0 {
                error = API.apiError("Server did not respond")
                shouldRetry = (e as NSError?)?.code == -1001 // retry if it was a timeout
            } else if Int64(data?.count ?? 0) < (response?.expectedContentLength ?? 0) {
                error = API.apiError("Server data was truncated")
                shouldRetry = true // transfer truncation, try again
            } else {
                DLog("(%@) GET %@ - RESULT: %@", apiServerLabel, expandedPath, code)
                error = e as NSError?
                shouldRetry = false
                if let d = data {
                    parsedData = try? JSONSerialization.jsonObject(with: d, options: [])
                }
            }
            
            if let e = error {
                if code > 399 && !shouldRetry {
                    if var backoff = existingBackOff {
                        DLog("(%@) Extending backoff for already throttled URL %@ by %@ seconds", apiServerLabel, expandedPath, backOffIncrement)
                        if backoff.nextIncrement < 3600.0 {
                            backoff.nextIncrement += backOffIncrement
                        }
                        backoff.nextAttemptAt = Date(timeIntervalSinceNow: backoff.nextIncrement)
                        DispatchQueue.main.async {
                            badLinks[expandedPath] = backoff
                        }
                    } else {
                        DLog("(%@) Placing URL %@ on the throttled list", apiServerLabel, expandedPath)
                        let newEntry = UrlBackOffEntry(
                            nextAttemptAt: Date(timeIntervalSinceNow: backOffIncrement),
                            nextIncrement: backOffIncrement)
                        DispatchQueue.main.async {
                            badLinks[expandedPath] = newEntry
                        }
                    }
                }
                DLog("(%@) GET %@ - FAILED: (code %@) %@", apiServerLabel, expandedPath, code, e.localizedDescription)
            }

            if Settings.dumpAPIResponsesInConsole, let d = data {
                DLog("API data from %@: %@", expandedPath, String(bytes: d, encoding: .utf8))
            }

            DispatchQueue.main.async {
                completion(code, headers, parsedData, error, shouldRetry)
            }
        }
        API.submitDataTask(task, on: restQueue)
    }
}
