
// Today widget and Watch init

import UIKit
import CoreData

let DATA_READONLY = true

let app = { () -> ExtensionGlobals! in
	Settings.checkMigration()
    DataManager.checkMigration()
    return ExtensionGlobals()
}()

let api = app

class ExtensionGlobals {

    var refreshesSinceLastLabelsCheck = [NSManagedObjectID:Int]()
    var refreshesSinceLastStatusCheck = [NSManagedObjectID:Int]()
    var isRefreshing = false
    var preferencesDirty = false
    var lastRepoCheck = never()

    func postNotificationOfType(type: PRNotificationType, forItem: NSManagedObject) {}

    func setMinimumBackgroundFetchInterval(interval: NSTimeInterval) -> Void {}

    func clearAllBadLinks() -> Void {}
}
