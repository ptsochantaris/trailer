import Foundation
import Maintini
import Semalot
import TrailerJson

typealias JSON = [String: Any]

enum DataResult {
    case success(headers: [AnyHashable: Any], data: Data), notFound, deleted, failed(code: Int), cancelled, ignored

    var logValue: String {
        switch self {
        case .success: "Success"
        case .deleted: "Deleted"
        case .notFound: "Not Found"
        case .cancelled: "Cancelled"
        case .ignored: "Ignored"
        case let .failed(code): "Error Code \(code)"
        }
    }
}

enum HTTP {
    static let gateKeeper = Semalot(tickets: 8)

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
            gateKeeper.returnTicket()
        }

        let result = try await getData(for: request, attempts: attempts, logPrefix: logPrefix)
        guard case let .success(_, data) = result else {
            return (nil, result)
        }

        if Logging.monitoringLog, let dataString = String(data: data, encoding: .utf8) {
            Logging.log("API data from \(request.url?.absoluteString ?? "<nil>"): \(dataString)")
        }

        do {
            let json = try await Task.detached { try data.withUnsafeBytes { try TrailerJson.parse(bytes: $0) } }.value
            return (json, result)
        } catch {
            if retryOnInvalidJson, attempts > 1 {
                Logging.log("Retrying on invalid JSON result (attempts left: \(attempts)): \(error)")
                try? await Task.sleep(nanoseconds: 5 * NSEC_PER_SEC)
                return try await getJsonData(for: request, attempts: attempts - 1, retryOnInvalidJson: true)
            }
            Logging.log("JSON error: \(error)")
            throw error
        }
    }

    static func getData(for request: URLRequest, attempts: Int, logPrefix: String? = nil) async throws -> DataResult {
        await Maintini.startMaintaining()
        defer {
            Task {
                await Maintini.endMaintaining()
            }
        }

        var attempt = attempts
        var retryDelay: UInt64 = 5
        while true {
            do {
                let response = try await urlSession.data(for: request)
                guard let httpResponse = response.1 as? HTTPURLResponse else {
                    throw ApiError.nonHttpResponse
                }

                let code = httpResponse.statusCode

                switch code {
                case 404:
                    return .notFound
                case 410:
                    return .deleted
                case 403, 502, 503:
                    // in case of throttle or ongoing GH deployment
                    throw ApiError.errorCode(code)
                case 400...:
                    return .failed(code: code)
                default:
                    return .success(headers: httpResponse.allHeaderFields, data: response.0)
                }
            } catch {
                if (error as NSError).code == -999 {
                    return .cancelled
                }

                let url = request.url?.absoluteString ?? "<nil>"
                attempt -= 1
                if attempt > 0 {
                    Logging.log("\(logPrefix.orEmpty)Will retry call to \(url) in \(retryDelay) seconds - \(error.localizedDescription)")
                    try? await Task.sleep(nanoseconds: retryDelay * NSEC_PER_SEC)
                    retryDelay += 2
                } else {
                    Logging.log("\(logPrefix.orEmpty)Failed call to \(url) - \(error.localizedDescription)")
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
            throw ApiError.invalidUrl(absolutePath)
        }

        let req = URLRequest(url: url)

        guard case let .success(_, data) = try await HTTP.getData(for: req, attempts: 1) else {
            throw ApiError.imageFetchFailed
        }

        guard let i = IMAGE_CLASS(data: data) else {
            throw ApiError.invalidImageData
        }

        return i
    }
}
