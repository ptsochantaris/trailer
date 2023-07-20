import Foundation
import TrailerJson

typealias JSON = [String: Any]

enum DataResult {
    case success(headers: [AnyHashable: Any]), notFound, deleted, failed(code: Int), cancelled

    var logValue: String {
        switch self {
        case .success: return "Success"
        case .deleted: return "Deleted"
        case .notFound: return "Not Found"
        case .cancelled: return "Cancelled"
        case let .failed(code): return "Error Code \(code)"
        }
    }
}

enum HTTP {
    private static let gateKeeper = Gate(tickets: 8)

    private static let urlSession: URLSession = {
        #if DEBUG
            #if os(iOS)
                let userAgent = "HouseTrip-Trailer-v\(currentAppVersion)-iOS-Development"
            #else
                let userAgent = "HouseTrip-Trailer-v\(currentAppVersion)-macOS-Development"
            #endif
        #else
            #if os(iOS)
                let userAgent = "HouseTrip-Trailer-v\(currentAppVersion)-iOS-Release"
            #else
                let userAgent = "HouseTrip-Trailer-v\(currentAppVersion)-macOS-Release"
            #endif
        #endif

        let config = URLSessionConfiguration.default
        config.httpShouldUsePipelining = true
        config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = 60
        config.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 1024 * 1024 * 1024, diskPath: ImageCache.shared.cacheDirectory)
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: config)
    }()

    static func getJsonData(for request: URLRequest, attempts: Int, logPrefix: String? = nil, retryOnInvalidJson: Bool = false) async throws -> (json: Any?, result: DataResult) {
        await gateKeeper.takeTicket()
        defer {
            gateKeeper.relaxedReturnTicket()
        }
        let (result, data) = try await getData(for: request, attempts: attempts, logPrefix: logPrefix)
        if case .success = result, monitoringLog, let dataString = String(data: data, encoding: .utf8) {
            DLog("API data from \(request.url?.absoluteString ?? "<nil>"): \(dataString)")
        }
        do {
            let json = try await Task.detached { try data.withUnsafeBytes { try TrailerJson.parse(bytes: $0) } }.value
            return (json, result)
        } catch {
            if retryOnInvalidJson, attempts > 1 {
                DLog("Retrying on invalid JSON result (attempts left: \(attempts)): \(error)")
                try? await Task.sleep(nanoseconds: 5 * NSEC_PER_SEC)
                return try await getJsonData(for: request, attempts: attempts - 1, retryOnInvalidJson: true)
            }
            DLog("JSON error: \(error)")
            throw error
        }
    }

    static func getData(for request: URLRequest, attempts: Int, logPrefix: String? = nil) async throws -> (result: DataResult, data: Data) {
        #if os(iOS)
            Task { @MainActor in
                BackgroundTask.registerForBackground()
            }
            defer {
                Task { @MainActor in
                    BackgroundTask.unregisterForBackground()
                }
            }
        #endif

        var attempt = attempts
        while true {
            do {
                let response = try await urlSession.data(for: request)
                guard let httpResponse = response.1 as? HTTPURLResponse else {
                    throw API.apiError("Network response was not a HTTP response")
                }

                let code = httpResponse.statusCode

                switch code {
                case 304:
                    throw API.apiError("Unexpected 304 received")
                case 404:
                    return (result: .notFound, data: Data())
                case 410:
                    return (result: .deleted, data: Data())
                case 403, 502, 503:
                    // in case of throttle or ongoing GH deployment
                    throw API.apiError("HTTP Code \(code) received")
                case 400...:
                    return (result: .failed(code: code), data: Data())
                default:
                    return (.success(headers: httpResponse.allHeaderFields), response.0)
                }
            } catch {
                if (error as NSError).code == -999 {
                    return (.cancelled, Data())
                }

                attempt -= 1
                if attempt > 0 {
                    let url = request.url?.absoluteString ?? "<nil>"
                    DLog("\(logPrefix.orEmpty)Will pause and retry call to \(url) - \(error.localizedDescription)")
                    try? await Task.sleep(nanoseconds: 5 * NSEC_PER_SEC)
                } else {
                    let url = request.url?.absoluteString ?? "<nil>"
                    DLog("\(logPrefix.orEmpty)Failed call to \(url) - \(error.localizedDescription)")
                    throw error
                }
            }
        }
    }

    @discardableResult
    static func avatar(from path: String) async throws -> IMAGE_CLASS {
        let connector = path.contains("?") ? "&" : "?"
        let absolutePath = "\(path)\(connector)s=128"

        guard let url = URL(string: absolutePath) else {
            throw API.apiError("Invalid URL: \(absolutePath)")
        }

        let req = URLRequest(url: url)
        let response = try await HTTP.getData(for: req, attempts: 1)
        guard let i = IMAGE_CLASS(data: response.data) else {
            throw API.apiError("Invalid image data")
        }
        return i
    }
}
