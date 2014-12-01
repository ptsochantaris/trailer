
extension NSDictionary {
	
	func ofk(key:AnyObject) -> AnyObject? {
		if let o:AnyObject = self.objectForKey(key) {
			if !o.isKindOfClass(NSNull) {
				return o
			}
		}
		return nil
	}
}
