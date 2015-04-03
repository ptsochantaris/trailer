import Foundation

extension NSDictionary {
	
	func ofk(key:AnyObject) -> AnyObject? {
		if let o:AnyObject = objectForKey(key) where !o.isKindOfClass(NSNull) {
			return o
		}
		return nil
	}
}
