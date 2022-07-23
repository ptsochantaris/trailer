import CoreData
import Foundation

final class NotificationQueue {
    private static var queue = [(NotificationType, NSManagedObjectID)]()

    static func add(type: NotificationType, for item: DataItem) {
        try? item.managedObjectContext?.obtainPermanentIDs(for: [item])
        queue.append((type, item.objectID))
    }

    static func clear() {
        queue.removeAll()
    }

    @MainActor
    static func commit(moc: NSManagedObjectContext) {
        let copy = queue
        clear()
        copy.forEach { type, itemId in
            if let storedItem = try? moc.existingObject(with: itemId) as? DataItem, storedItem.apiServer.lastSyncSucceeded {
                #if os(iOS)
                    NotificationManager.postNotification(type: type, for: storedItem)
                #else
                    app.postNotification(type: type, for: storedItem)
                #endif
            }
        }
    }
}
