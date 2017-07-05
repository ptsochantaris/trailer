// Tweaked for Swift 3. Originally created by, and with many thanks to:

/**
//  md5.swift
//  PHPFramework
//  Created by Wesley de Groot on 28-02-16.
//  Copyright © 2016 WDGWV. All rights reserved.
MD5Hashing
A real native Swift 2 MD5 function
Created by Wesley de Groot. (Twitter: @wesdegroot)
GitHub: @wdg
Thanks for using!
*/

import Foundation

struct MD5Hashing {
	private static let shift : [UInt32] = [7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21]
	private static let table: [UInt32] = (0 ..< 64).map {UInt32(0x100000000 * abs(sin(Double($0 + 1))))}

	/**
	MD5 Generator Function.
	- Parameter str: The string what needs to be encoded.
	- Returns: MD5 hashed string
	*/
	static func md5(str: String) -> String {

		var message: [UInt8] = [UInt8](str.utf8)

		let messageLenBits = UInt64(message.count) * 8
		message.append(0x80)
		while message.count % 64 != 56 {
			message.append(0)
		}

		let lengthBytes = UnsafeMutableRawPointer.allocate(bytes: 8, alignedTo: 1)
		lengthBytes.storeBytes(of: messageLenBits.littleEndian, as: UInt64.self)
		let buffer = UnsafeRawBufferPointer(start: lengthBytes, count: 8)
		message += Array(buffer)

		var a: UInt32 = 0x67452301
		var b: UInt32 = 0xEFCDAB89
		var c: UInt32 = 0x98BADCFE
		var d: UInt32 = 0x10325476

		let messageStartPointer = UnsafeRawPointer(message)
		for chunkOffset in stride(from: 0, to: message.count, by: 64) {
			let chunk = (messageStartPointer + chunkOffset).assumingMemoryBound(to: UInt32.self)
			let originalA = a
			let originalB = b
			let originalC = c
			let originalD = d
			for j in 0 ..< 64 {
				var f : UInt32 = 0
				var bufferIndex = j
				let round = j >> 4
				switch round {
				case 0:
					f = (b & c) | (~b & d)
				case 1:
					f = (b & d) | (c & ~d)
					bufferIndex = (bufferIndex * 5 + 1) & 0x0F
				case 2:
					f = b ^ c ^ d
					bufferIndex = (bufferIndex * 3 + 5) & 0x0F
				case 3:
					f = c ^ (b | ~d)
					bufferIndex = (bufferIndex * 7) & 0x0F
				default:
					assert(false)
				}
				let sa = shift[(round << 2) | (j&3)]
				let tmp = a &+ f &+ UInt32(littleEndian: chunk[bufferIndex]) &+ table[j]
				a = d
				d = c
				c = b
				b = b &+ (tmp << sa | tmp >> (32 - sa))
			}
			a = a &+ originalA
			b = b &+ originalB
			c = c &+ originalC
			d = d &+ originalD
		}

		let result = [UInt8](repeating: 0, count: 16)
		let resultPointer = UnsafeMutableRawPointer(mutating: result)

		for (i, n) in [0: a, 4: b, 8: c, 12: d] {
			resultPointer.storeBytes(of: n.littleEndian, toByteOffset: i, as: UInt32.self)
		}

		return result.map({ String(format: "%02X", $0) }).joined()
	}
}
