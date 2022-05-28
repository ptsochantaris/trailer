import UIKit

extension UINavigationController {

	open override var disablesAutomaticKeyboardDismissal: Bool {
        return topViewController!.disablesAutomaticKeyboardDismissal
	}
}
