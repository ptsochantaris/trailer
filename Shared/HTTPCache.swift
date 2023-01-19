import Foundation
import NIOCore
import NIOHTTP1

final actor HTTPCache {
    private let cacheDirectory: String = {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return appSupportURL.appendingPathComponent("build.bru.Trailer").path
    }()

    init() {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: cacheDirectory) {
            Task {
                await expireAncientFiles()
            }
        } else {
            try! fileManager.createDirectory(atPath: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
        }
    }

    private let store = NSCache<WrappedUrl, CachedResponse>()

    private final class WrappedUrl: NSObject {
        let key: String

        init(_ key: String) {
            self.key = key
        }

        override var hash: Int {
            key.hashValue
        }

        override func isEqual(_ object: Any?) -> Bool {
            if let value = object as? WrappedUrl {
                return value.key == key
            } else {
                return false
            }
        }
    }

    final class CachedResponse {
        let bytes: ByteBuffer
        let etag: String
        var cachedIn: String?

        init(bytes: ByteBuffer, etag: String) {
            self.bytes = bytes
            self.etag = etag
        }

        fileprivate func write(to path: String) throws {
            cachedIn = path
            let binPath = URL(fileURLWithPath: "\(path).bin")
            try bytes.asData.write(to: binPath, options: .atomic)
            let etagPath = URL(fileURLWithPath: "\(path).etag")
            try etag.data(using: .utf8)?.write(to: etagPath, options: .atomic)
        }

        fileprivate init(contentsOf path: String) throws {
            let etagPath = URL(fileURLWithPath: "\(path).etag")
            guard let etag = String(data: try Data(contentsOf: etagPath), encoding: .utf8) else {
                throw API.apiError("Invalid Etag data in http cache")
            }
            self.etag = etag
            let binPath = URL(fileURLWithPath: "\(path).bin")
            bytes = ByteBuffer(data: try Data(contentsOf: binPath))
        }
    }

    func reset() {
        store.removeAllObjects()
    }

    subscript(key: String) -> CachedResponse? {
        let wrappedKey = WrappedUrl(key)
        if let obj = store.object(forKey: wrappedKey) {
            return obj
        }
        let filename = "\(cacheDirectory)/\(key.fileHash)"
        if let obj = try? CachedResponse(contentsOf: filename) {
            obj.cachedIn = filename
            store.setObject(obj, forKey: wrappedKey)
            return obj
        }
        return nil
    }

    func touch(at path: String) {
        let fileManager = FileManager.default
        let now = Date()
        let binPath = "\(path).bin"
        try? fileManager.setAttributes([.creationDate: now, .modificationDate: now], ofItemAtPath: binPath)
        let etagPath = "\(path).etag"
        try? fileManager.setAttributes([.creationDate: now, .modificationDate: now], ofItemAtPath: etagPath)
    }

    func set(response value: CachedResponse, for key: String) {
        store.setObject(value, forKey: WrappedUrl(key))
        let filename = "\(cacheDirectory)/\(key.fileHash)"
        try? value.write(to: filename)
    }

    private func expireAncientFiles() {
        let now = Date()
        let fileManager = FileManager.default
        for f in try! fileManager.contentsOfDirectory(atPath: cacheDirectory) {
            do {
                let path = cacheDirectory.appending(pathComponent: f)
                let attributes = try fileManager.attributesOfItem(atPath: path)
                if let date = attributes[.creationDate] as? Date {
                    if now.timeIntervalSince(date) > (3600 * 24 * 30) {
                        try fileManager.removeItem(atPath: path)
                        DLog("Removed old cached data: %@", path)
                    }
                } else {
                    DLog("Removed cached data with no modification date: %@", path)
                }
            } catch {
                DLog("File error when removing old cached data: %@", error.localizedDescription)
            }
        }
    }
}
