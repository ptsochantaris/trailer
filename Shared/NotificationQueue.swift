import CoreData
import Foundation

@MainActor
enum NotificationQueue {
    private static var queue = [(NotificationType, NSManagedObjectID)]()

    static func add(type: NotificationType, for item: DataItem) {
        try? item.managedObjectContext?.obtainPermanentIDs(for: [item])
        let oid = item.objectID
        Task {
            queue.append((type, oid))
        }
    }

    static func clear() {
        queue.removeAll()
    }

    static func commit() {
        let moc = DataManager.main
        queue.forEach { type, itemId in
            if let storedItem = try? moc.existingObject(with: itemId) as? DataItem, storedItem.apiServer.lastSyncSucceeded {
                #if os(iOS)
                    NotificationManager.postNotification(type: type, for: storedItem)
                #else
                    app.postNotification(type: type, for: storedItem)
                #endif
            }
        }
        clear()
    }
}
