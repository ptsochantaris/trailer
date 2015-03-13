import Foundation

extension NSString {
	
	func md5hash() -> NSString {
		let digestLen = Int(CC_MD5_DIGEST_LENGTH)
		let result = UnsafeMutablePointer<CUnsignedChar>.alloc(digestLen)

		CC_MD5(
			cStringUsingEncoding(NSUTF8StringEncoding),
			CC_LONG(lengthOfBytesUsingEncoding(NSUTF8StringEncoding)),
			result)

		var hash = NSMutableString()
		for i in 0..<digestLen {
			hash.appendFormat("%02X", result[i])
		}

		result.destroy()

		return String(hash)
	}

	func parseFromHex() -> UInt32 {
		var safe = stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
		safe = safe.stringByTrimmingCharactersInSet(NSCharacterSet.symbolCharacterSet())
		let s = NSScanner(string: safe)
		var result:UInt32 = 0
		s.scanHexInt(&result)
		return result
	}
}
