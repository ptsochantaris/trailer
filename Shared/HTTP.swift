//
//  HTTP.swift
//  Trailer
//
//  Created by Paul Tsochantaris on 22/05/2022.
//

import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1

enum DataResult {
    case success(headers: HTTPHeaders, cachedIn: String?), notFound, deleted, failed(code: UInt)

    var logValue: String {
        switch self {
        case .success: return "Success"
        case .deleted: return "Deleted"
        case .notFound: return "Not Found"
        case let .failed(code): return "Error Code \(code)"
        }
    }
}

extension ByteBuffer {
    var asData: Data {
        Data(buffer: self)
    }
}

enum HTTP {
    private static let gateKeeper = Gate(tickets: 8)

    #if DEBUG
        #if os(iOS)
            private static let userAgent = "HouseTrip-Trailer-v\(currentAppVersion)-iOS-Development"
        #else
            private static let userAgent = "HouseTrip-Trailer-v\(currentAppVersion)-macOS-Development"
        #endif
    #else
        #if os(iOS)
            private static let userAgent = "HouseTrip-Trailer-v\(currentAppVersion)-iOS-Release"
        #else
            private static let userAgent = "HouseTrip-Trailer-v\(currentAppVersion)-macOS-Release"
        #endif
    #endif

    private static let httpClient = HTTPClient(eventLoopGroupProvider: .createNew,
                                               configuration: HTTPClient.Configuration(certificateVerification: .fullVerification,
                                                                                       redirectConfiguration: .disallow,
                                                                                       decompression: .enabled(limit: .none)))

    static func getJsonData(for request: HTTPClientRequest, attempts: Int, checkCache: Bool) async throws -> (json: Any, result: DataResult) {
        await gateKeeper.takeTicket()
        defer {
            gateKeeper.relaxedReturnTicket()
        }
        let (result, data) = try await getData(for: request, attempts: attempts, checkCache: checkCache)
        if case .success = result, Settings.dumpAPIResponsesInConsole {
            DLog("API data from %@: %@", S(request.url), data.description)
        }
        let json = try await Task.detached {
            try JSONSerialization.jsonObject(with: data.asData)
        }.value
        return (json, result)
    }

    private static let getCache = HTTPCache()

    static func getData(for request: HTTPClientRequest, attempts: Int, checkCache: Bool) async throws -> (result: DataResult, data: ByteBuffer) {
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

        let cachedEntry: HTTPCache.CachedResponse?
        var request = request
        request.headers.add(name: "User-Agent", value: userAgent)
        if checkCache {
            cachedEntry = await getCache[request.url]
            if let etag = cachedEntry?.etag {
                request.headers.add(name: "If-None-Match", value: etag)
            }
        } else {
            cachedEntry = nil
        }

        var attempt = attempts
        while attempt > 0 {
            do {
                let response = try await httpClient.execute(request, timeout: .seconds(60))
                let code = response.status.code

                switch code {
                case 304:
                    if let cachedEntry {
                        // DLog("304 - \(cachedEntry.etag) - \(request.url)")
                        if let location = cachedEntry.cachedIn {
                            Task {
                                await getCache.touch(at: location)
                            }
                        }
                        return (.success(headers: response.headers, cachedIn: cachedEntry.cachedIn), cachedEntry.bytes)
                    } else {
                        throw API.apiError("Unexpected 304 received")
                    }
                case 404:
                    return (result: .notFound, data: ByteBuffer())
                case 410:
                    return (result: .deleted, data: ByteBuffer())
                case 502, 503: // in case of throttle or ongoing GH deployment
                    throw API.apiError("HTTP Code \(code) received")
                case 400...:
                    return (result: .failed(code: code), data: ByteBuffer())
                default:
                    let data = try await response.body.collect(upTo: 10240 * 1024 * 1024) // 1Gb
                    if let etag = response.headers["ETag"].first {
                        let cached = HTTPCache.CachedResponse(bytes: data, etag: etag)
                        let key = request.url
                        Task {
                            await getCache.set(response: cached, for: key) // sets the cache location as well
                        }
                        return (.success(headers: response.headers, cachedIn: cached.cachedIn), data)
                    } else {
                        return (.success(headers: response.headers, cachedIn: nil), data)
                    }
                }
            } catch {
                attempt -= 1
                if attempt > 0 {
                    DLog("Will pause and retry call to %@", request.url)
                    try? await Task.sleep(nanoseconds: 5 * NSEC_PER_SEC)
                } else {
                    DLog("Failed API call to %@", request.url)
                    throw error
                }
            }
        }
        throw API.apiError("HTTP Error")
    }

    @discardableResult
    static func avatar(from path: String) async throws -> (IMAGE_CLASS, String?) {
        let connector = path.contains("?") ? "&" : "?"
        let absolutePath = "\(path)\(connector)s=128"

        // if image exists, return without checking in with the server
        if let existingEntry = await getCache[absolutePath], let i = IMAGE_CLASS(data: existingEntry.bytes.asData) {
            return (i, existingEntry.cachedIn)
        }

        let req = HTTPClientRequest(url: absolutePath)
        let response = try await HTTP.getData(for: req, attempts: 1, checkCache: false)
        guard let i = IMAGE_CLASS(data: response.data.asData) else {
            throw API.apiError("Invalid image data")
        }
        if case let .success(_, cachePath) = response.result {
            return (i, cachePath)
        } else {
            return (i, nil)
        }
    }
}
