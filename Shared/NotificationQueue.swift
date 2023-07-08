import CoreData
import Foundation
import TrailerQL

enum NotificationQueue {
    private static var queue = List<(NotificationType, NSManagedObjectID)>()

    static func add(type: NotificationType, for item: DataItem) {
        try? item.managedObjectContext?.obtainPermanentIDs(for: [item])
        let oid = item.objectID
        Task { @MainActor in
            queue.append((type, oid))
        }
    }

    @MainActor
    static func clear() {
        queue.removeAll()
    }

    @MainActor
    static func commit() {
        let moc = DataManager.main
        while let (type, itemId) = queue.pop() {
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
