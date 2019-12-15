
import Foundation
import CoreData

final class NotificationQueue {

	private static var queue = [(NotificationType, NSManagedObjectID)]()

	static func add(type: NotificationType, for item: DataItem) {
        try? item.managedObjectContext?.obtainPermanentIDs(for: [item])
        queue.append((type, item.objectID))
	}

	static func clear() {
		queue.removeAll()
	}

	static func commit() {
		for (type, itemId) in queue {
            if let storedItem = try? DataManager.main.existingObject(with: itemId) as? DataItem, storedItem.apiServer.lastSyncSucceeded {
                #if os(iOS)
                NotificationManager.postNotification(type: type, for: storedItem)
                #else
                app.postNotification(type: type, for: storedItem)
                #endif
            }
		}
 		queue.removeAll()
	}
}
