import Foundation
import UIKit

extension Notification.Name {
    static let showPreferences = Self("ShowPreferences")
    static let tabBarSetUpdate = Self("TabBarSetUpdate")
}

extension UIViewController {
    @MainActor
    func dismiss(animated: Bool) async {
        await withCheckedContinuation { continuation in
            dismiss(animated: animated) {
                continuation.resume()
            }
        }
    }
}
