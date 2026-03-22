import Foundation
import UIKit

extension Notification.Name {
    static let notificationSelected = Self("NotificationSelected")
    static let showPreferences = Self("ShowPreferences")
    static let tabBarSetUpdate = Self("TabBarSetUpdate")
    static let highlightItem = Self("HighlightItem")
    static let focusFilter = Self("FocusFilter")
    static let openComment = Self("OpenComment")
    static let resetView = Self("ResetView")
    static let dbSaved = Self("DbSaved")
}

extension UIViewController {
    func dismiss(animated: Bool) async {
        await withCheckedContinuation { continuation in
            dismiss(animated: animated) {
                continuation.resume()
            }
        }
    }
}
