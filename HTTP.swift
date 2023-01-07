//
//  HTTP.swift
//  Trailer
//
//  Created by Paul Tsochantaris on 22/05/2022.
//

import Foundation

enum DataResult {
    case success(headers: [AnyHashable: Any]), notFound, deleted, failed(code: Int)

    var logValue: String {
        switch self {
        case .success: return "Success"
        case .deleted: return "Deleted"
        case .notFound: return "Not Found"
        case let .failed(code): return "Error Code \(code)"
        }
    }
}

@globalActor
enum HttpActor {
    actor ActorType {}
    static let shared = ActorType()
}

@HttpActor
enum HTTP {
    final actor GateKeeper {
        private var counter: Int
        init(entries: Int) {
            counter = entries
        }

        func waitForGate() async {
            while counter < 0 {
                await Task.yield()
            }
            counter -= 1
        }

        func signalGate() {
            counter += 1
        }
    }

    private static let gateKeeper = GateKeeper(entries: 8)

    private static var urlSessionConfig: URLSessionConfiguration {
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
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        config.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 1024 * 1024 * 1024, diskPath: API.cacheDirectory)
        return config
    }

    private static let urlSession = URLSession(configuration: urlSessionConfig, delegate: nil, delegateQueue: nil)

    static func getJsonData(for request: URLRequest, attempts: Int) async throws -> (json: Any, result: DataResult) {
        await gateKeeper.waitForGate()
        defer {
            Task {
                await gateKeeper.signalGate()
            }
        }
        let (data, result) = try await getData(for: request, attempts: attempts)
        if Settings.dumpAPIResponsesInConsole {
            DLog("API data from %@: %@", S(request.url?.path), String(bytes: data, encoding: .utf8))
        }
        let json = try await Task.detached { try JSONSerialization.jsonObject(with: data, options: []) }.value
        return (json, result)
    }

    nonisolated static func getData(for request: URLRequest, attempts: Int) async throws -> (data: Data, response: DataResult) {
        var attempt = attempts
        while attempt > 0 {
            do {
                let data: Data
                let response: URLResponse
                if #available(macOS 12.0, iOS 15.0, *) {
                    (data, response) = try await urlSession.data(for: request)
                } else {
                    (data, response) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
                        let task = urlSession.dataTask(with: request) { data, response, error in
                            if let data, let response {
                                continuation.resume(returning: (data, response))
                            } else {
                                continuation.resume(throwing: error ?? API.apiError("No data and no error from http call"))
                            }
                        }
                        task.resume()
                    }
                }
                guard let response = response as? HTTPURLResponse else {
                    throw API.apiError("Invalid HTTP response")
                }
                let code = response.statusCode
                switch code {
                case 404:
                    return (data, .notFound)
                case 410:
                    return (data, .deleted)
                case 502, 503, -1001: // in case of throttle or ongoing GH deployment or timeout
                    throw API.apiError("HTTP Code \(code) received")
                case 400...:
                    return (data, .failed(code: code))
                default: return (data, .success(headers: response.allHeaderFields))
                }

            } catch {
                attempt -= 1
                if attempt > 0 {
                    if let url = request.url {
                        DLog("Will pause and retry call to %@", url)
                    }
                    try? await Task.sleep(nanoseconds: 5 * NSEC_PER_SEC)
                } else {
                    if let url = request.url {
                        DLog("Failed API call to %@", url)
                    }
                    throw error
                }
            }
        }
        throw API.apiError("HTTP Error")
    }
}
