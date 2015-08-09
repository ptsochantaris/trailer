
import UIKit

extension UINavigationController {
	override public func disablesAutomaticKeyboardDismissal() -> Bool {
		return topViewController!.disablesAutomaticKeyboardDismissal()
	}
}
