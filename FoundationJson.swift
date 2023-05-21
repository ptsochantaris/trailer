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
        var whitespace = 0
        while let byte = peek(offset: whitespace) {
            switch byte {
            case UInt8._quote:
                readerIndex += whitespace
                return try readString()
            case ._openbrace:
                readerIndex += whitespace
                return try parseObject()
            case ._openbracket:
                readerIndex += whitespace
                return try parseArray()
            case UInt8._charF, UInt8._charT:
                readerIndex += whitespace
                return try readBool()
            case UInt8._charN:
                readerIndex += whitespace
                try readNull()
                return nil
            case UInt8._minus, UInt8._zero ... UInt8._nine:
                readerIndex += whitespace
                return try parseNumber()
            case ._newline, ._return, ._space, ._tab:
                whitespace += 1
                continue
            default:
                throw JSONError.unexpectedCharacter(ascii: byte, characterIndex: readerIndex)
            }
        }
        
        throw JSONError.unexpectedEndOfFile
    }
    
    // MARK: - Parse Array -
    
    private func parseArray() throws -> [Any] {
        precondition(read() == ._openbracket)
        
        // parse first value or end immediatly
        switch try consumeWhitespace() {
        case ._newline, ._return, ._space, ._tab:
            preconditionFailure("Expected that all white space is consumed")
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
            guard let value = try parseValue() else {
                continue
            }
            array.append(value)
            
            // consume the whitespace after the value before the comma
            let ascii = try consumeWhitespace()
            switch ascii {
            case ._newline, ._return, ._space, ._tab:
                preconditionFailure("Expected that all white space is consumed")
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
                continue
            default:
                throw JSONError.unexpectedCharacter(ascii: ascii, characterIndex: readerIndex)
            }
        }
    }
    
    // MARK: - Object parsing -
    
    private func parseObject() throws -> JSON {
        precondition(read() == ._openbrace)
        
        // parse first value or end immediatly
        switch try consumeWhitespace() {
        case ._newline, ._return, ._space, ._tab:
            preconditionFailure("Expected that all white space is consumed")
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
            let key = try readString()
            let colon = try consumeWhitespace()
            guard colon == ._colon else {
                throw JSONError.unexpectedCharacter(ascii: colon, characterIndex: readerIndex)
            }
            readerIndex += 1
            try consumeWhitespace()
            if let value = try parseValue() {
                object[key] = value
            }
            
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
        let res = array[readerIndex]
        readerIndex += 1
        return res
    }
    
    private func peek(offset: Int = 0) -> UInt8? {
        guard readerIndex + offset < endIndex else {
            return nil
        }
        
        return array[readerIndex + offset]
    }
    
    @discardableResult
    private func consumeWhitespace() throws -> UInt8 {
        while let ascii = peek() {
            switch ascii {
            case ._newline, ._return, ._space, ._tab:
                readerIndex += 1
            default:
                return ascii
            }
        }
        
        throw JSONError.unexpectedEndOfFile
    }
    
    private func readBool() throws -> Bool {
        switch read() {
        case UInt8._charT:
            guard read() == UInt8(ascii: "r"),
                  read() == UInt8(ascii: "u"),
                  read() == UInt8(ascii: "e")
            else {
                if readerIndex >= endIndex {
                    throw JSONError.unexpectedEndOfFile
                }
                
                throw JSONError.unexpectedCharacter(ascii: peek(offset: -1)!, characterIndex: readerIndex - 1)
            }
            
            return true
        case UInt8._charF:
            guard read() == UInt8(ascii: "a"),
                  read() == UInt8(ascii: "l"),
                  read() == UInt8(ascii: "s"),
                  read() == UInt8(ascii: "e")
            else {
                if readerIndex >= endIndex {
                    throw JSONError.unexpectedEndOfFile
                }
                
                throw JSONError.unexpectedCharacter(ascii: peek(offset: -1)!, characterIndex: readerIndex - 1)
            }
            
            return false
        default:
            preconditionFailure("Expected to have `t` or `f` as first character")
        }
    }
    
    private func readNull() throws {
        guard read() == UInt8._charN,
              read() == UInt8(ascii: "u"),
              read() == UInt8(ascii: "l"),
              read() == UInt8(ascii: "l")
        else {
            if readerIndex >= endIndex {
                throw JSONError.unexpectedEndOfFile
            }
            
            throw JSONError.unexpectedCharacter(ascii: peek(offset: -1)!, characterIndex: readerIndex - 1)
        }
    }
    
    // MARK: String
    
    private enum EscapedSequenceError: Swift.Error {
        case expectedLowSurrogateUTF8SequenceAfterHighSurrogate(index: Int)
        case unexpectedEscapedCharacter(ascii: UInt8, index: Int)
        case couldNotCreateUnicodeScalarFromUInt32(index: Int, unicodeScalarValue: UInt32)
    }
    
    private func readString() throws -> String {
        guard read() == ._quote else {
            throw JSONError.unexpectedCharacter(ascii: peek(offset: -1)!, characterIndex: readerIndex - 1)
        }
        var stringStartIndex = readerIndex
        var copy = 0
        var output: String?
        
        while let byte = peek(offset: copy) {
            switch byte {
            case UInt8._quote:
                readerIndex += copy + 1
                guard var result = output else {
                    // if we don't have an output string we create a new string
                    return makeString(at: stringStartIndex ..< stringStartIndex + copy)
                }
                // if we have an output string we append
                result += makeString(at: stringStartIndex ..< stringStartIndex + copy)
                return result
                
            case 0 ... 31:
                // All Unicode characters may be placed within the
                // quotation marks, except for the characters that must be escaped:
                // quotation mark, reverse solidus, and the control characters (U+0000
                // through U+001F).
                var string = output ?? ""
                let errorIndex = readerIndex + copy
                string += makeString(at: stringStartIndex ... errorIndex)
                throw JSONError.unescapedControlCharacterInString(ascii: byte, in: string, index: errorIndex)
                
            case UInt8._backslash:
                readerIndex += copy
                if output != nil {
                    output! += makeString(at: stringStartIndex ..< stringStartIndex + copy)
                } else {
                    output = makeString(at: stringStartIndex ..< stringStartIndex + copy)
                }
                
                let escapedStartIndex = readerIndex
                
                do {
                    let escaped = try parseEscapeSequence()
                    output! += escaped
                    stringStartIndex = readerIndex
                    copy = 0
                } catch let EscapedSequenceError.unexpectedEscapedCharacter(ascii, failureIndex) {
                    output! += makeString(at: escapedStartIndex ..< readerIndex)
                    throw JSONError.unexpectedEscapedCharacter(ascii: ascii, in: output!, index: failureIndex)
                } catch let EscapedSequenceError.expectedLowSurrogateUTF8SequenceAfterHighSurrogate(failureIndex) {
                    output! += makeString(at: escapedStartIndex ..< readerIndex)
                    throw JSONError.expectedLowSurrogateUTF8SequenceAfterHighSurrogate(in: output!, index: failureIndex)
                } catch let EscapedSequenceError.couldNotCreateUnicodeScalarFromUInt32(failureIndex, unicodeScalarValue) {
                    output! += makeString(at: escapedStartIndex ..< readerIndex)
                    throw JSONError.couldNotCreateUnicodeScalarFromUInt32(
                        in: output!, index: failureIndex, unicodeScalarValue: unicodeScalarValue
                    )
                }
                
            default:
                copy += 1
                continue
            }
        }
        
        throw JSONError.unexpectedEndOfFile
    }
    
    private func makeString(at range: some RangeExpression<Int>) -> String {
        let bytes = array[range]
        let count = bytes.count
        return String(unsafeUninitializedCapacity: count) { pointer in
            _ = pointer.initialize(fromContentsOf: bytes)
            return count
        }
    }
    
    private func parseEscapeSequence() throws -> String {
        precondition(read() == ._backslash, "Expected to have an backslash first")
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
    
    private func parseNumber() throws -> Any {
        var pastControlChar: ControlCharacter = .operand
        var numbersSinceControlChar: UInt
        var hasLeadingZero: Bool
        
        // parse first character
        
        guard let ascii = peek() else {
            preconditionFailure("Why was this function called, if there is no further character")
        }
        switch ascii {
        case UInt8._zero:
            numbersSinceControlChar = 1
            hasLeadingZero = true
        case UInt8._one ... UInt8._nine:
            numbersSinceControlChar = 1
            hasLeadingZero = false
        case UInt8._minus:
            numbersSinceControlChar = 0
            hasLeadingZero = false
        default:
            preconditionFailure("Why was this function called, if there is no 0...9 or -")
        }
        
        var numberchars = 1
        
        // parse everything else
        while let byte = peek(offset: numberchars) {
            switch byte {
            case UInt8._zero:
                if hasLeadingZero {
                    throw JSONError.numberWithLeadingZero(index: readerIndex + numberchars)
                }
                if numbersSinceControlChar == 0, pastControlChar == .operand {
                    // the number started with a minus. this is the leading zero.
                    hasLeadingZero = true
                }
                numberchars += 1
                numbersSinceControlChar += 1
            case UInt8._zero ... UInt8._nine:
                if hasLeadingZero {
                    throw JSONError.numberWithLeadingZero(index: readerIndex + numberchars)
                }
                numberchars += 1
                numbersSinceControlChar += 1
            case UInt8._period:
                guard numbersSinceControlChar > 0, pastControlChar == .operand else {
                    throw JSONError.unexpectedCharacter(ascii: byte, characterIndex: readerIndex + numberchars)
                }
                
                numberchars += 1
                hasLeadingZero = false
                pastControlChar = .decimalPoint
                numbersSinceControlChar = 0
                
            case UInt8._charE, UInt8._charCapitalE:
                guard numbersSinceControlChar > 0,
                      pastControlChar == .operand || pastControlChar == .decimalPoint
                else {
                    throw JSONError.unexpectedCharacter(ascii: byte, characterIndex: readerIndex + numberchars)
                }
                
                numberchars += 1
                hasLeadingZero = false
                pastControlChar = .exp
                numbersSinceControlChar = 0
            case UInt8._minus, UInt8._plus:
                guard numbersSinceControlChar == 0, pastControlChar == .exp else {
                    throw JSONError.unexpectedCharacter(ascii: byte, characterIndex: readerIndex + numberchars)
                }
                
                numberchars += 1
                pastControlChar = .expOperator
                numbersSinceControlChar = 0
            case ._closebrace, ._closebracket, ._comma, ._newline, ._return, ._space, ._tab:
                guard numbersSinceControlChar > 0 else {
                    throw JSONError.unexpectedCharacter(ascii: byte, characterIndex: readerIndex + numberchars)
                }
                let numberStartIndex = readerIndex
                readerIndex += numberchars
                
                let stringValue = makeString(at: numberStartIndex ..< readerIndex)
                switch pastControlChar {
                case .decimalPoint:
                    guard let result = Float(stringValue) else {
                        throw JSONError.numberIsNotRepresentableInSwift(parsed: stringValue)
                    }
                    return result
                case .exp, .expOperator:
                    throw JSONError.numberIsNotRepresentableInSwift(parsed: stringValue)
                case .operand:
                    guard let result = Int(stringValue) else {
                        throw JSONError.numberIsNotRepresentableInSwift(parsed: stringValue)
                    }
                    return result
                }
            default:
                throw JSONError.unexpectedCharacter(ascii: byte, characterIndex: readerIndex + numberchars)
            }
        }
        
        guard numbersSinceControlChar > 0 else {
            throw JSONError.unexpectedEndOfFile
        }
        
        defer { readerIndex = endIndex }
        return makeString(at: readerIndex...)
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
        case numberWithLeadingZero(index: Int)
        case numberIsNotRepresentableInSwift(parsed: String)
        case invalidUTF8Sequence(Data, characterIndex: Int)
    }
    
    static func jsonObject(with data: Data) throws -> Any {
        do {
            let parser = FoundationJson(bytes: Array(data))
            if let result = try parser.parse() {
                return result
            } else {
                return NSNull()
            }
            
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
            case let .numberWithLeadingZero(index: index):
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.propertyListReadCorrupt.rawValue, userInfo: [
                    NSDebugDescriptionErrorKey: #"Number with leading zero around character \#(index)."#
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
    static let _charT = UInt8(ascii: "t")
    static let _charN = UInt8(ascii: "n")
    static let _charE = UInt8(ascii: "e")
    static let _charCapitalE = UInt8(ascii: "E")
}
