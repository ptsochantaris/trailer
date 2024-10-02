import CoreData
import Foundation
import Lista
import TrailerQL

enum NotificationQueue {
    @MainActor
    private static var queue = Lista<(NotificationType, NSManagedObjectID)>()

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
        let queueCopy = Array(queue)
        queue.removeAll()
        Task {
            let moc = DataManager.main
            for (type, itemId) in queueCopy {
                if let storedItem = try? moc.existingObject(with: itemId) as? DataItem,
                   storedItem.apiServer.lastSyncSucceeded {
                    await NotificationManager.shared.postNotification(type: type, for: storedItem)
                    await Task.yield()
                }
            }
        }
    }
}
