//
//  HTTP.swift
//  Trailer
//
//  Created by Paul Tsochantaris on 22/05/2022.
//

import Foundation

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
    
    static func getJsonData(for request: URLRequest) async throws -> (json: Any, response: HTTPURLResponse) {
        await gateKeeper.waitForGate()
        defer {
            Task {
                await gateKeeper.signalGate()
            }
        }
        let (data, response) = try await getData(for: request)
        if Settings.dumpAPIResponsesInConsole {
            DLog("API data from %@: %@", S(request.url?.path), String(bytes: data, encoding: .utf8))
        }
        let json = try await Task.detached { try JSONSerialization.jsonObject(with: data, options: []) }.value
        return (json, response)
    }

    nonisolated static func getData(for request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse) {
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
        return (data, response)
    }
}
