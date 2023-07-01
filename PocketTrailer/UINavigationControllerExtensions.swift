import UIKit

extension UINavigationController {
    override open var disablesAutomaticKeyboardDismissal: Bool {
        topViewController!.disablesAutomaticKeyboardDismissal
    }
}
