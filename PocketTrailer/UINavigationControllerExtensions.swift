
import UIKit

extension UINavigationController {

	public override var disablesAutomaticKeyboardDismissal: Bool {
		get {
			return topViewController!.disablesAutomaticKeyboardDismissal
		}
		set {
			super.disablesAutomaticKeyboardDismissal = newValue
		}
	}
}
