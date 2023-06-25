import Foundation

// This is derived lightweight version of Apple's new Swift Founfation JSON decoder here: https://github.com/apple/swift-corelibs-foundation/blob/bafd3d0f800397a15a3d092979ee7e788082feee/Sources/Foundation/JSONSerialization.swift
// It is significanlty simplified with the following changes:
// - Decoding only
// - Uses only Swift data types - warning: This makes it incompatible with JSNOSerialisation output, not a drop-in replacement
// - Supports UTF8 JSON data only
// - null objects or array entries are thrown away, they are not kept
// - Floating point numbers are parsed as Float, not Double
// - Does not support exponent numbers, only integers and double floats

typealias JSON = [String: Any]

@available(macOS 11.0, iOS 14.0, *)
extension ArraySlice<UInt8> {
    var asString: String {
        String(unsafeUninitializedCapacity: count) { pointer in
            _ = pointer.initialize(fromContentsOf: self)
            return count
        }
    }
}

@available(macOS 11.0, iOS 14.0, *)
final class FoundationJson {
    private let array: [UInt8]
    private let endIndex: Int
    private var readerIndex = 0

    init(bytes: [UInt8]) {
        array = bytes
        endIndex = bytes.endIndex
    }

    func parse() throws -> Any? {
        try consumeWhitespace()
        return try parseValue()
    }

    // MARK: Generic Value Parsing

    private func parseValue() throws -> Any? {
        while let byte = read() {
            switch byte {
            case ._quote:
                return try readString()
            case ._openbrace:
                return try parseObject()
            case ._openbracket:
                return try parseArray()
            case ._charF:
                try skip(4)
                return false
            case ._charT:
                try skip(3)
                return true
            case ._charN:
                try skip(3)
                return nil
            case ._minus:
                return try parseNumber(positive: false)
            case ._zero ... ._nine:
                return try parseNumber(positive: true)
            case ._newline, ._return, ._space, ._tab:
                readerIndex += 1
            default:
                throw JSONError.unexpectedCharacter(ascii: byte, characterIndex: readerIndex)
            }
        }

        throw JSONError.unexpectedEndOfFile
    }

    // MARK: - Parse Array -

    private func parseArray() throws -> [Any] {
        // parse first value or end immediatly
        switch try consumeWhitespace() {
        case ._closebracket:
            // if the first char after whitespace is a closing bracket, we found an empty array
            readerIndex += 1
            return []
        default:
            break
        }

        var array = [Any]()
        array.reserveCapacity(10)

        // parse values
        while true {
            if let value = try parseValue() {
                array.append(value)
            }

            // consume the whitespace after the value before the comma
            let ascii = try consumeWhitespace()
            switch ascii {
            case ._closebracket:
                readerIndex += 1
                return array

            case ._comma:
                // consume the comma
                readerIndex += 1
                // consume the whitespace before the next value
                if try consumeWhitespace() == ._closebracket {
                    // the foundation json implementation does support trailing commas
                    readerIndex += 1
                    return array
                }

            default:
                throw JSONError.unexpectedCharacter(ascii: ascii, characterIndex: readerIndex)
            }
        }
    }

    // MARK: - Object parsing -

    private func parseObject() throws -> JSON {
        // parse first value or end immediatly
        switch try consumeWhitespace() {
        case ._closebrace:
            // if the first char after whitespace is a closing bracket, we found an empty array
            readerIndex += 1
            return [:]
        default:
            break
        }

        var object = JSON()
        object.reserveCapacity(20)

        while true {
            readerIndex += 1 // quote
            let key = try readString()
            let colon = try consumeWhitespace()
            guard colon == ._colon else {
                throw JSONError.unexpectedCharacter(ascii: colon, characterIndex: readerIndex)
            }
            readerIndex += 1
            try consumeWhitespace()
            object[key] = try parseValue()

            let commaOrBrace = try consumeWhitespace()
            switch commaOrBrace {
            case ._closebrace:
                readerIndex += 1
                return object
            case ._comma:
                readerIndex += 1
                if try consumeWhitespace() == ._closebrace {
                    // the foundation json implementation does support trailing commas
                    readerIndex += 1
                    return object
                }
                continue
            default:
                throw JSONError.unexpectedCharacter(ascii: commaOrBrace, characterIndex: readerIndex)
            }
        }
    }

    // document reading

    private func read() -> UInt8? {
        guard readerIndex < endIndex else {
            readerIndex = endIndex
            return nil
        }
        defer {
            readerIndex += 1
        }
        return array[readerIndex]
    }

    private func peekPrevious() -> UInt8 {
        array[readerIndex - 1]
    }

    @discardableResult
    private func consumeWhitespace() throws -> UInt8 {
        while readerIndex < endIndex {
            let ascii = array[readerIndex]
            switch ascii {
            case ._newline, ._return, ._space, ._tab:
                readerIndex += 1
            default:
                return ascii
            }
        }

        throw JSONError.unexpectedEndOfFile
    }

    private func skip(_ num: Int) throws {
        readerIndex += num

        guard readerIndex < endIndex else {
            throw JSONError.unexpectedEndOfFile
        }
    }

    // MARK: String

    private enum EscapedSequenceError: Swift.Error {
        case expectedLowSurrogateUTF8SequenceAfterHighSurrogate(index: Int)
        case unexpectedEscapedCharacter(ascii: UInt8, index: Int)
        case couldNotCreateUnicodeScalarFromUInt32(index: Int, unicodeScalarValue: UInt32)
    }

    private func readString() throws -> String {
        var stringStartIndex = readerIndex
        var output: String?

        while let byte = read() {
            switch byte {
            case ._quote:
                let currentCharIndex = readerIndex - 1
                if let output {
                    return output + array[stringStartIndex ..< currentCharIndex].asString
                } else {
                    return array[stringStartIndex ..< currentCharIndex].asString
                }

            case 0 ... 31:
                let currentCharIndex = readerIndex - 1
                // All Unicode characters may be placed within the
                // quotation marks, except for the characters that must be escaped:
                // quotation mark, reverse solidus, and the control characters (U+0000
                // through U+001F).
                let string: String
                if let output {
                    string = output + array[stringStartIndex ... currentCharIndex].asString
                } else {
                    string = array[stringStartIndex ... currentCharIndex].asString
                }
                throw JSONError.unescapedControlCharacterInString(ascii: byte, in: string, index: currentCharIndex)

            case ._backslash:
                let currentCharIndex = readerIndex - 1
                if let existing = output {
                    output = existing + array[stringStartIndex ..< currentCharIndex].asString
                } else {
                    output = array[stringStartIndex ..< currentCharIndex].asString
                }

                do {
                    if let existing = output {
                        output = try existing + parseEscapeSequence()
                    } else {
                        output = try parseEscapeSequence()
                    }
                    stringStartIndex = readerIndex

                } catch let EscapedSequenceError.unexpectedEscapedCharacter(ascii, failureIndex) {
                    output! += array[currentCharIndex ..< readerIndex].asString
                    throw JSONError.unexpectedEscapedCharacter(ascii: ascii, in: output!, index: failureIndex)
                } catch let EscapedSequenceError.expectedLowSurrogateUTF8SequenceAfterHighSurrogate(failureIndex) {
                    output! += array[currentCharIndex ..< readerIndex].asString
                    throw JSONError.expectedLowSurrogateUTF8SequenceAfterHighSurrogate(in: output!, index: failureIndex)
                } catch let EscapedSequenceError.couldNotCreateUnicodeScalarFromUInt32(failureIndex, unicodeScalarValue) {
                    output! += array[currentCharIndex ..< readerIndex].asString
                    throw JSONError.couldNotCreateUnicodeScalarFromUInt32(in: output!, index: failureIndex, unicodeScalarValue: unicodeScalarValue)
                }

            default:
                break
            }
        }

        throw JSONError.unexpectedEndOfFile
    }

    private func parseEscapeSequence() throws -> String {
        guard let ascii = read() else {
            throw JSONError.unexpectedEndOfFile
        }

        switch ascii {
        case 0x22: return "\""
        case 0x5C: return "\\"
        case 0x2F: return "/"
        case 0x62: return "\u{08}" // \b
        case 0x66: return "\u{0C}" // \f
        case 0x6E: return "\u{0A}" // \n
        case 0x72: return "\u{0D}" // \r
        case 0x74: return "\u{09}" // \t
        case 0x75:
            let character = try parseUnicodeSequence()
            return String(character)
        default:
            throw EscapedSequenceError.unexpectedEscapedCharacter(ascii: ascii, index: readerIndex - 1)
        }
    }

    private func parseUnicodeSequence() throws -> Unicode.Scalar {
        // we build this for utf8 only for now.
        let bitPattern = try parseUnicodeHexSequence()

        // check if high surrogate
        let isFirstByteHighSurrogate = bitPattern & 0xFC00 // nil everything except first six bits
        if isFirstByteHighSurrogate == 0xD800 {
            // if we have a high surrogate we expect a low surrogate next
            let highSurrogateBitPattern = bitPattern
            guard let escapeChar = read(),
                  let uChar = read()
            else {
                throw JSONError.unexpectedEndOfFile
            }

            guard escapeChar == UInt8(ascii: #"\"#), uChar == UInt8(ascii: "u") else {
                throw EscapedSequenceError.expectedLowSurrogateUTF8SequenceAfterHighSurrogate(index: readerIndex - 1)
            }

            let lowSurrogateBitBattern = try parseUnicodeHexSequence()
            let isSecondByteLowSurrogate = lowSurrogateBitBattern & 0xFC00 // nil everything except first six bits
            guard isSecondByteLowSurrogate == 0xDC00 else {
                // we are in an escaped sequence. for this reason an output string must have
                // been initialized
                throw EscapedSequenceError.expectedLowSurrogateUTF8SequenceAfterHighSurrogate(index: readerIndex - 1)
            }

            let highValue = UInt32(highSurrogateBitPattern - 0xD800) * 0x400
            let lowValue = UInt32(lowSurrogateBitBattern - 0xDC00)
            let unicodeValue = highValue + lowValue + 0x10000
            guard let unicode = Unicode.Scalar(unicodeValue) else {
                throw EscapedSequenceError.couldNotCreateUnicodeScalarFromUInt32(
                    index: readerIndex, unicodeScalarValue: unicodeValue
                )
            }
            return unicode
        }

        guard let unicode = Unicode.Scalar(bitPattern) else {
            throw EscapedSequenceError.couldNotCreateUnicodeScalarFromUInt32(
                index: readerIndex, unicodeScalarValue: UInt32(bitPattern)
            )
        }
        return unicode
    }

    private func parseUnicodeHexSequence() throws -> UInt16 {
        // As stated in RFC-8259 an escaped unicode character is 4 HEXDIGITs long
        // https://tools.ietf.org/html/rfc8259#section-7
        let startIndex = readerIndex
        guard let firstHex = read(),
              let secondHex = read(),
              let thirdHex = read(),
              let forthHex = read()
        else {
            throw JSONError.unexpectedEndOfFile
        }

        guard let first = FoundationJson.hexAsciiTo4Bits(firstHex),
              let second = FoundationJson.hexAsciiTo4Bits(secondHex),
              let third = FoundationJson.hexAsciiTo4Bits(thirdHex),
              let forth = FoundationJson.hexAsciiTo4Bits(forthHex)
        else {
            let hexString = String(decoding: [firstHex, secondHex, thirdHex, forthHex], as: Unicode.UTF8.self)
            throw JSONError.invalidHexDigitSequence(hexString, index: startIndex)
        }
        let firstByte = UInt16(first) << 4 | UInt16(second)
        let secondByte = UInt16(third) << 4 | UInt16(forth)

        let bitPattern = UInt16(firstByte) << 8 | UInt16(secondByte)

        return bitPattern
    }

    private static func hexAsciiTo4Bits(_ ascii: UInt8) -> UInt8? {
        switch ascii {
        case 48 ... 57:
            return ascii - 48
        case 65 ... 70:
            // uppercase letters
            return ascii - 55
        case 97 ... 102:
            // lowercase letters
            return ascii - 87
        default:
            return nil
        }
    }

    // MARK: Numbers

    private enum ControlCharacter {
        case operand
        case decimalPoint
        case exp
        case expOperator
    }

    private func parseNumber(positive: Bool) throws -> Any {
        let startIndex = readerIndex - 1

        var pastControlChar: ControlCharacter = .operand
        var numbersSinceControlChar = positive

        while let byte = read() {
            switch byte {
            case ._zero ... ._nine:
                numbersSinceControlChar = true

            case ._period:
                guard numbersSinceControlChar, pastControlChar == .operand else {
                    throw JSONError.unexpectedCharacter(ascii: byte, characterIndex: readerIndex - 1)
                }
                pastControlChar = .decimalPoint
                numbersSinceControlChar = false

            case ._charCapitalE, ._charE:
                guard numbersSinceControlChar,
                      pastControlChar == .operand || pastControlChar == .decimalPoint
                else {
                    throw JSONError.unexpectedCharacter(ascii: byte, characterIndex: readerIndex - 1)
                }
                pastControlChar = .exp
                numbersSinceControlChar = false

            case ._minus, ._plus:
                guard !numbersSinceControlChar, pastControlChar == .exp else {
                    throw JSONError.unexpectedCharacter(ascii: byte, characterIndex: readerIndex - 1)
                }
                pastControlChar = .expOperator
                numbersSinceControlChar = false

            case ._closebrace, ._closebracket, ._comma, ._newline, ._return, ._space, ._tab:
                guard numbersSinceControlChar else {
                    throw JSONError.unexpectedCharacter(ascii: byte, characterIndex: readerIndex - 1)
                }

                readerIndex -= 1
                switch pastControlChar {
                case .decimalPoint:
                    let stringValue = array[startIndex ..< readerIndex].asString
                    guard let result = Float(stringValue) else {
                        throw JSONError.numberIsNotRepresentableInSwift(parsed: stringValue)
                    }
                    return result
                case .exp, .expOperator:
                    let stringValue = array[startIndex ..< readerIndex].asString
                    throw JSONError.numberIsNotRepresentableInSwift(parsed: stringValue)
                case .operand:
                    let numberIndex: Int
                    var dec: Int
                    if positive {
                        numberIndex = startIndex
                        dec = 1
                    } else {
                        numberIndex = startIndex + 1
                        dec = -1
                    }

                    var index = readerIndex
                    var total = 0
                    while index > numberIndex {
                        index -= 1
                        total += Int(array[index] - 48) * dec
                        dec *= 10
                    }
                    return total
                }

            default:
                throw JSONError.unexpectedCharacter(ascii: byte, characterIndex: readerIndex - 1)
            }
        }

        guard numbersSinceControlChar else {
            throw JSONError.unexpectedEndOfFile
        }

        defer { readerIndex = endIndex }
        return array[readerIndex...].asString
    }

    private enum JSONError: Swift.Error, Equatable {
        case cannotConvertInputDataToUTF8
        case unexpectedCharacter(ascii: UInt8, characterIndex: Int)
        case unexpectedEndOfFile
        case tooManyNestedArraysOrDictionaries(characterIndex: Int)
        case invalidHexDigitSequence(String, index: Int)
        case unexpectedEscapedCharacter(ascii: UInt8, in: String, index: Int)
        case unescapedControlCharacterInString(ascii: UInt8, in: String, index: Int)
        case expectedLowSurrogateUTF8SequenceAfterHighSurrogate(in: String, index: Int)
        case couldNotCreateUnicodeScalarFromUInt32(in: String, index: Int, unicodeScalarValue: UInt32)
        case numberIsNotRepresentableInSwift(parsed: String)
        case invalidUTF8Sequence(Data, characterIndex: Int)
    }

    static func jsonObject(with data: Data) throws -> Any {
        do {
            let array = [UInt8](data)
            let parser = FoundationJson(bytes: array)
            return try parser.parse() ?? NSNull()

        } catch let error as JSONError {
            switch error {
            case .cannotConvertInputDataToUTF8:
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.propertyListReadCorrupt.rawValue, userInfo: [
                    NSDebugDescriptionErrorKey: "Cannot convert input string to valid utf8 input."
                ])
            case .unexpectedEndOfFile:
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.propertyListReadCorrupt.rawValue, userInfo: [
                    NSDebugDescriptionErrorKey: "Unexpected end of file during JSON parse."
                ])
            case let .unexpectedCharacter(_, characterIndex):
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.propertyListReadCorrupt.rawValue, userInfo: [
                    NSDebugDescriptionErrorKey: "Invalid value around character \(characterIndex)."
                ])
            case .expectedLowSurrogateUTF8SequenceAfterHighSurrogate:
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.propertyListReadCorrupt.rawValue, userInfo: [
                    NSDebugDescriptionErrorKey: "Unexpected end of file during string parse (expected low-surrogate code point but did not find one)."
                ])
            case .couldNotCreateUnicodeScalarFromUInt32:
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.propertyListReadCorrupt.rawValue, userInfo: [
                    NSDebugDescriptionErrorKey: "Unable to convert hex escape sequence (no high character) to UTF8-encoded character."
                ])
            case let .unexpectedEscapedCharacter(_, _, index):
                // we lower the failure index by one to match the darwin implementations counting
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.propertyListReadCorrupt.rawValue, userInfo: [
                    NSDebugDescriptionErrorKey: "Invalid escape sequence around character \(index - 1)."
                ])
            case let .tooManyNestedArraysOrDictionaries(characterIndex: characterIndex):
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.propertyListReadCorrupt.rawValue, userInfo: [
                    NSDebugDescriptionErrorKey: "Too many nested arrays or dictionaries around character \(characterIndex + 1)."
                ])
            case let .invalidHexDigitSequence(string, index: index):
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.propertyListReadCorrupt.rawValue, userInfo: [
                    NSDebugDescriptionErrorKey: #"Invalid hex encoded sequence in "\#(string)" at \#(index)."#
                ])
            case .unescapedControlCharacterInString(ascii: let ascii, in: _, index: let index) where ascii == UInt8._backslash:
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.propertyListReadCorrupt.rawValue, userInfo: [
                    NSDebugDescriptionErrorKey: #"Invalid escape sequence around character \#(index)."#
                ])
            case .unescapedControlCharacterInString(ascii: _, in: _, index: let index):
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.propertyListReadCorrupt.rawValue, userInfo: [
                    NSDebugDescriptionErrorKey: #"Unescaped control character around character \#(index)."#
                ])
            case let .numberIsNotRepresentableInSwift(parsed: parsed):
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.propertyListReadCorrupt.rawValue, userInfo: [
                    NSDebugDescriptionErrorKey: #"Number \#(parsed) is not representable in Swift."#
                ])
            case let .invalidUTF8Sequence(data, characterIndex: index):
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.propertyListReadCorrupt.rawValue, userInfo: [
                    NSDebugDescriptionErrorKey: #"Invalid UTF-8 sequence \#(data) starting from character \#(index)."#
                ])
            }
        } catch {
            preconditionFailure("Only `JSONError` expected")
        }
    }
}

private extension UInt8 {
    static let _space = UInt8(ascii: " ")
    static let _return = UInt8(ascii: "\r")
    static let _newline = UInt8(ascii: "\n")
    static let _tab = UInt8(ascii: "\t")

    static let _colon = UInt8(ascii: ":")
    static let _comma = UInt8(ascii: ",")
    static let _period = UInt8(ascii: ".")

    static let _openbrace = UInt8(ascii: "{")
    static let _closebrace = UInt8(ascii: "}")

    static let _openbracket = UInt8(ascii: "[")
    static let _closebracket = UInt8(ascii: "]")

    static let _quote = UInt8(ascii: "\"")
    static let _backslash = UInt8(ascii: "\\")

    static let _minus = UInt8(ascii: "-")
    static let _plus = UInt8(ascii: "+")

    static let _zero = UInt8(ascii: "0")
    static let _one = UInt8(ascii: "1")
    static let _nine = UInt8(ascii: "9")

    static let _charF = UInt8(ascii: "f")
    static let _charA = UInt8(ascii: "a")
    static let _charL = UInt8(ascii: "l")
    static let _charS = UInt8(ascii: "s")
    static let _charE = UInt8(ascii: "e")

    static let _charR = UInt8(ascii: "r")
    static let _charU = UInt8(ascii: "u")
    static let _charT = UInt8(ascii: "t")
    static let _charN = UInt8(ascii: "n")
    static let _charCapitalE = UInt8(ascii: "E")
}
