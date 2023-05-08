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

private final class JSONParser {
    private let reader: DocumentReader
    private var depth = 0

    init(bytes: [UInt8]) {
        reader = DocumentReader(array: bytes)
    }

    func parse() throws -> Any? {
        try reader.consumeWhitespace()
        let value = try parseValue()
        #if DEBUG
            defer {
                guard self.depth == 0 else {
                    preconditionFailure("Expected to end parsing with a depth of 0")
                }
            }
        #endif

        // ensure only white space is remaining
        var whitespace = 0
        while let next = reader.peek(offset: whitespace) {
            switch next {
            case ._newline, ._return, ._space, ._tab:
                whitespace += 1
                continue
            default:
                throw JSONError.unexpectedCharacter(ascii: next, characterIndex: reader.readerIndex + whitespace)
            }
        }

        return value
    }

    // MARK: Generic Value Parsing

    private func parseValue() throws -> Any? {
        var whitespace = 0
        while let byte = reader.peek(offset: whitespace) {
            switch byte {
            case UInt8._quote:
                reader.moveReaderIndex(forwardBy: whitespace)
                return try reader.readString()
            case ._openbrace:
                reader.moveReaderIndex(forwardBy: whitespace)
                return try parseObject()
            case ._openbracket:
                reader.moveReaderIndex(forwardBy: whitespace)
                return try parseArray()
            case UInt8._charF, UInt8._charT:
                reader.moveReaderIndex(forwardBy: whitespace)
                return try reader.readBool()
            case UInt8._charN:
                reader.moveReaderIndex(forwardBy: whitespace)
                try reader.readNull()
                return nil
            case UInt8._minus, UInt8._zero ... UInt8._nine:
                reader.moveReaderIndex(forwardBy: whitespace)
                return try reader.parseNumber()
            case ._newline, ._return, ._space, ._tab:
                whitespace += 1
                continue
            default:
                throw JSONError.unexpectedCharacter(ascii: byte, characterIndex: reader.readerIndex)
            }
        }

        throw JSONError.unexpectedEndOfFile
    }

    // MARK: - Parse Array -

    private func parseArray() throws -> [Any] {
        precondition(reader.read() == ._openbracket)
        guard depth < 512 else {
            throw JSONError.tooManyNestedArraysOrDictionaries(characterIndex: reader.readerIndex - 1)
        }
        depth += 1
        defer { depth -= 1 }

        // parse first value or end immediatly
        switch try reader.consumeWhitespace() {
        case ._newline, ._return, ._space, ._tab:
            preconditionFailure("Expected that all white space is consumed")
        case ._closebracket:
            // if the first char after whitespace is a closing bracket, we found an empty array
            reader.moveReaderIndex(forwardBy: 1)
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
            let ascii = try reader.consumeWhitespace()
            switch ascii {
            case ._newline, ._return, ._space, ._tab:
                preconditionFailure("Expected that all white space is consumed")
            case ._closebracket:
                reader.moveReaderIndex(forwardBy: 1)
                return array
            case ._comma:
                // consume the comma
                reader.moveReaderIndex(forwardBy: 1)
                // consume the whitespace before the next value
                if try reader.consumeWhitespace() == ._closebracket {
                    // the foundation json implementation does support trailing commas
                    reader.moveReaderIndex(forwardBy: 1)
                    return array
                }
                continue
            default:
                throw JSONError.unexpectedCharacter(ascii: ascii, characterIndex: reader.readerIndex)
            }
        }
    }

    // MARK: - Object parsing -

    private func parseObject() throws -> JSON {
        precondition(reader.read() == ._openbrace)
        guard depth < 512 else {
            throw JSONError.tooManyNestedArraysOrDictionaries(characterIndex: reader.readerIndex - 1)
        }
        depth += 1
        defer { depth -= 1 }

        // parse first value or end immediatly
        switch try reader.consumeWhitespace() {
        case ._newline, ._return, ._space, ._tab:
            preconditionFailure("Expected that all white space is consumed")
        case ._closebrace:
            // if the first char after whitespace is a closing bracket, we found an empty array
            reader.moveReaderIndex(forwardBy: 1)
            return [:]
        default:
            break
        }

        var object = JSON()
        object.reserveCapacity(20)

        while true {
            let key = try reader.readString()
            let colon = try reader.consumeWhitespace()
            guard colon == ._colon else {
                throw JSONError.unexpectedCharacter(ascii: colon, characterIndex: reader.readerIndex)
            }
            reader.moveReaderIndex(forwardBy: 1)
            try reader.consumeWhitespace()
            if let value = try parseValue() {
                object[key] = value
            }

            let commaOrBrace = try reader.consumeWhitespace()
            switch commaOrBrace {
            case ._closebrace:
                reader.moveReaderIndex(forwardBy: 1)
                return object
            case ._comma:
                reader.moveReaderIndex(forwardBy: 1)
                if try reader.consumeWhitespace() == ._closebrace {
                    // the foundation json implementation does support trailing commas
                    reader.moveReaderIndex(forwardBy: 1)
                    return object
                }
                continue
            default:
                throw JSONError.unexpectedCharacter(ascii: commaOrBrace, characterIndex: reader.readerIndex)
            }
        }
    }

    private final class DocumentReader {
        private let array: [UInt8]
        private let endIndex: Int

        private(set) var readerIndex = 0

        private var readableBytes: Int {
            endIndex - readerIndex
        }

        var isEOF: Bool {
            readerIndex >= endIndex
        }

        init(array: [UInt8]) {
            self.array = array
            self.endIndex = array.endIndex
        }

        func read() -> UInt8? {
            guard readerIndex < endIndex else {
                readerIndex = endIndex
                return nil
            }

            defer { readerIndex += 1 }

            return array[readerIndex]
        }

        func peek(offset: Int = 0) -> UInt8? {
            guard readerIndex + offset < endIndex else {
                return nil
            }

            return array[readerIndex + offset]
        }

        func moveReaderIndex(forwardBy offset: Int) {
            readerIndex += offset
        }

        @discardableResult
        func consumeWhitespace() throws -> UInt8 {
            var whitespace = 0
            while let ascii = peek(offset: whitespace) {
                switch ascii {
                case ._newline, ._return, ._space, ._tab:
                    whitespace += 1
                    continue
                default:
                    readerIndex += whitespace
                    return ascii
                }
            }

            throw JSONError.unexpectedEndOfFile
        }

        func readString() throws -> String {
            try readUTF8StringTillNextUnescapedQuote()
        }

        func readBool() throws -> Bool {
            switch read() {
            case UInt8._charT:
                guard read() == UInt8(ascii: "r"),
                      read() == UInt8(ascii: "u"),
                      read() == UInt8(ascii: "e")
                else {
                    guard !isEOF else {
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
                    guard !isEOF else {
                        throw JSONError.unexpectedEndOfFile
                    }

                    throw JSONError.unexpectedCharacter(ascii: peek(offset: -1)!, characterIndex: readerIndex - 1)
                }

                return false
            default:
                preconditionFailure("Expected to have `t` or `f` as first character")
            }
        }

        func readNull() throws {
            guard read() == UInt8._charN,
                  read() == UInt8(ascii: "u"),
                  read() == UInt8(ascii: "l"),
                  read() == UInt8(ascii: "l")
            else {
                guard !isEOF else {
                    throw JSONError.unexpectedEndOfFile
                }

                throw JSONError.unexpectedCharacter(ascii: peek(offset: -1)!, characterIndex: readerIndex - 1)
            }
        }

        // MARK: - Private Methods -

        // MARK: String

        enum EscapedSequenceError: Swift.Error {
            case expectedLowSurrogateUTF8SequenceAfterHighSurrogate(index: Int)
            case unexpectedEscapedCharacter(ascii: UInt8, index: Int)
            case couldNotCreateUnicodeScalarFromUInt32(index: Int, unicodeScalarValue: UInt32)
        }

        private func readUTF8StringTillNextUnescapedQuote() throws -> String {
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
                        output! += makeString(at: escapedStartIndex ..< self.readerIndex)
                        throw JSONError.unexpectedEscapedCharacter(ascii: ascii, in: output!, index: failureIndex)
                    } catch let EscapedSequenceError.expectedLowSurrogateUTF8SequenceAfterHighSurrogate(failureIndex) {
                        output! += makeString(at: escapedStartIndex ..< self.readerIndex)
                        throw JSONError.expectedLowSurrogateUTF8SequenceAfterHighSurrogate(in: output!, index: failureIndex)
                    } catch let EscapedSequenceError.couldNotCreateUnicodeScalarFromUInt32(failureIndex, unicodeScalarValue) {
                        output! += makeString(at: escapedStartIndex ..< self.readerIndex)
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
            String(decoding: array[range], as: UTF8.self)
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

            guard let first = DocumentReader.hexAsciiTo4Bits(firstHex),
                  let second = DocumentReader.hexAsciiTo4Bits(secondHex),
                  let third = DocumentReader.hexAsciiTo4Bits(thirdHex),
                  let forth = DocumentReader.hexAsciiTo4Bits(forthHex)
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

        func parseNumber() throws -> Any {
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

            defer { self.readerIndex = endIndex }
            return makeString(at: readerIndex...)
        }
    }
}

extension UInt8 {
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

enum JSONError: Swift.Error, Equatable {
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

enum FoundationJson {
    static func jsonObject(with data: Data) throws -> Any {
        do {
            let parser = JSONParser(bytes: Array(data))
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
