
extension NSString {
	
	func md5hash() -> NSString {
		let digestLen = Int(CC_MD5_DIGEST_LENGTH)
		let result = UnsafeMutablePointer<CUnsignedChar>.alloc(digestLen)

		CC_MD5(
			self.cStringUsingEncoding(NSUTF8StringEncoding),
			CC_LONG(self.lengthOfBytesUsingEncoding(NSUTF8StringEncoding)),
			result)

		var hash = NSMutableString()
		for i in 0..<digestLen {
			hash.appendFormat("%02X", result[i])
		}

		result.destroy()

		return String(hash)
	}

	func parseFromHex() -> UInt64 {
		var safe = self.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
		safe = safe.stringByTrimmingCharactersInSet(NSCharacterSet.symbolCharacterSet())
		let s = NSScanner(string: safe)
		var result:UInt64 = 0
		s.scanHexLongLong(&result)
		return result
	}
}
