
import Foundation

final class NotificationQueue {

	private static var queue = [(NotificationType, DataItem)]()

	class func add(type: NotificationType, for item: DataItem) {
		queue.append((type, item))
	}

	class func clear() {
		queue.removeAll()
	}

	class func commit() {
		for (type, item) in queue {
			if !item.isDeleted && item.apiServer.lastSyncSucceeded {
				#if os(iOS)
					NotificationManager.postNotification(type: type, for: item)
				#else
					app.postNotification(type: type, for: item)
				#endif
			}
		}
		queue.removeAll()
	}
}
