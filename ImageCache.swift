#if canImport(AppKit)
    import AppKit
    import Foundation
#else
    import UIKit
#endif

final actor ImageCache {
    static let shared = ImageCache()

    nonisolated let cacheDirectory: String = {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return appSupportURL.appendingPathComponent("build.bru.Trailer").path
    }()

    private init() {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: cacheDirectory) {
            Task {
                await expireAncientFiles()
            }
        } else {
            try! fileManager.createDirectory(atPath: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
        }
    }

    func store(_ image: IMAGE_CLASS, from url: String) -> URL? {
        let filename = "\(cacheDirectory)/\(url.fileHash).bin"
        let url = URL(fileURLWithPath: filename)

        do {
            #if canImport(AppKit)
                if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                   let jpg = NSBitmapImageRep(cgImage: cgImage).representation(using: .jpeg, properties: [:]) {
                    try jpg.write(to: url)
                    return url
                }
            #else
                if let jpg = image.jpegData(compressionQuality: 0.7) {
                    try jpg.write(to: url)
                    return url
                }
            #endif
        } catch {}

        return nil
    }

    private func expireAncientFiles() {
        let now = Date()
        let fileManager = FileManager.default
        for f in try! fileManager.contentsOfDirectory(atPath: cacheDirectory) {
            do {
                let path = cacheDirectory.appending(pathComponent: f)
                if path.hasSuffix(".etag") {
                    try fileManager.removeItem(atPath: path)
                    DLog("Removed old cached data: \(path)")

                } else if path.hasSuffix(".bin") {
                    let attributes = try fileManager.attributesOfItem(atPath: path)
                    if let date = attributes[.creationDate] as? Date {
                        if now.timeIntervalSince(date) > (3600 * 24 * 30) {
                            try fileManager.removeItem(atPath: path)
                            DLog("Removed old cached data: \(path)")
                        }
                    } else {
                        DLog("Removed cached data with no modification date: \(path)")
                    }
                }
            } catch {
                DLog("File error when removing old cached data: \(error.localizedDescription)")
            }
        }
    }
}
