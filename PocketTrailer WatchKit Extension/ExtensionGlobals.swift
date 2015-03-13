//
//  WatchKitGlobals.swift
//  Trailer
//
//  Created by Paul Tsochantaris on 11/03/2015.
//
//

import UIKit
import CoreData

class ExtensionGlobals {

    class func go() {
        app = ExtensionGlobals()
        api = app
        DataManager.checkMigration()
    }

    class func done()
    {
        app = nil
        api = nil
    }

    var refreshesSinceLastLabelsCheck = [NSManagedObjectID:Int]()
    var refreshesSinceLastStatusCheck = [NSManagedObjectID:Int]()
    var isRefreshing = false

    func postNotificationOfType(type: PRNotificationType, forItem: NSManagedObject) {}

    func setMinimumBackgroundFetchInterval(interval: NSTimeInterval) -> Void {}
}
