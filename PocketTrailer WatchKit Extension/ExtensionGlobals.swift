//
//  WatchKitGlobals.swift
//  Trailer
//
//  Created by Paul Tsochantaris on 11/03/2015.
//
//

import UIKit
import CoreData

let app = { () -> ExtensionGlobals in
    DataManager.checkMigration()
    return ExtensionGlobals()
}()

let api = app

class ExtensionGlobals {

    var refreshesSinceLastLabelsCheck = [NSManagedObjectID:Int]()
    var refreshesSinceLastStatusCheck = [NSManagedObjectID:Int]()
    var isRefreshing = false

    func postNotificationOfType(type: PRNotificationType, forItem: NSManagedObject) {}

    func setMinimumBackgroundFetchInterval(interval: NSTimeInterval) -> Void {}
}