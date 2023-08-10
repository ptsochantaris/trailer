import Foundation

enum Keychain {
    // With many thanks to https://www.advancedswift.com/secure-private-data-keychain-swift/

    enum KeychainError: Error {
        case failure(OSStatus)
    }

    private static let service = "com.housetrip.Trailer"

    private static func baseQuery(account: String) -> [CFString: Any] {
        [kSecAttrService: service, kSecAttrAccount: account, kSecClass: kSecClassGenericPassword]
    }

    static func write(data: Data?, account: String) throws {
        var query = baseQuery(account: account)
        var status: OSStatus

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
            throw KeychainError.failure(status)
        }
    }

    static func read(account: String) throws -> Data? {
        var query = baseQuery(account: account)
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
            throw KeychainError.failure(status)
        }
    }
}
