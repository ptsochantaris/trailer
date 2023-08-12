import Foundation

protocol DataRepresentable {
    var asData: Data? { get }
    init?(data: Data?)
}

extension String: DataRepresentable {
    init?(data: Data?) {
        guard let data else { return nil }
        self.init(data: data, encoding: .utf8)
    }

    var asData: Data? {
        data(using: .utf8)
    }
}

final class Keychain {
    // With many thanks to https://www.advancedswift.com/secure-private-data-keychain-swift/

    @propertyWrapper
    struct Property<Value: DataRepresentable> {
        let key: String
        let keychain: Keychain

        init(key: String, service: String, teamId: String) {
            self.key = key
            keychain = Keychain(service: service, teamId: teamId)
        }

        var wrappedValue: Value? {
            get {
                let data = keychain[key]
                return Value(data: data)
            }
            set {
                keychain[key] = newValue?.asData
            }
        }
    }

    enum KeychainError: LocalizedError {
        case readFailure(OSStatus)
        case writeFailure(OSStatus)

        var errorDescription: String? {
            switch self {
            case let .readFailure(status):
                "Keychain read failed with error \(status)"
            case let .writeFailure(status):
                "Keychain write failed with error \(status)"
            }
        }
    }

    private let templateQuery: [CFString: Any]

    init(service: String, teamId: String) {
        templateQuery = [kSecClass: kSecClassGenericPassword,
                         kSecAttrService: service,
                         kSecUseDataProtectionKeychain: kCFBooleanTrue!,
                         kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
                         kSecAttrAccessGroup: "\(teamId).\(service)"]
    }

    func read(from key: String) throws -> Data? {
        var query = templateQuery
        query[kSecAttrAccount] = key
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = kCFBooleanTrue

        var itemCopy: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &itemCopy)
        switch status {
        case errSecSuccess:
            return itemCopy as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.readFailure(status)
        }
    }

    func write(data: Data?, to key: String) throws {
        var query = templateQuery
        var status: OSStatus

        query[kSecAttrAccount] = key

        if let data {
            query[kSecValueData] = data
            status = SecItemAdd(query as CFDictionary, nil)

            switch status {
            case errSecDuplicateItem:
                query[kSecValueData] = nil
                status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)

            default:
                break
            }

        } else {
            status = SecItemDelete(query as CFDictionary)
            switch status {
            case errSecItemNotFound, errSecSuccess:
                return
            default:
                break
            }
        }

        if status != errSecSuccess {
            throw KeychainError.writeFailure(status)
        }
    }

    subscript(key: String) -> Data? {
        get { try! read(from: key) }
        set { try! write(data: newValue, to: key) }
    }
}
