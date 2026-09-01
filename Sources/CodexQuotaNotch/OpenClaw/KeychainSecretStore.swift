import Foundation
import Security

public enum KeychainSecretStoreError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case invalidStoredValue
}

public final class KeychainSecretStore: SecretStore {
    public static let defaultService = "com.codexquotanotch.openclaw"

    private let service: String

    public init(service: String = KeychainSecretStore.defaultService) {
        self.service = service
    }

    public func read(key: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainSecretStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainSecretStoreError.invalidStoredValue
        }
        return value
    }

    public func write(_ value: String, key: String) throws {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        let update: [CFString: Any] = [kSecValueData: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainSecretStoreError.unexpectedStatus(updateStatus)
        }

        var item = query
        item[kSecValueData] = data
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainSecretStoreError.unexpectedStatus(addStatus)
        }
    }

    public func delete(key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSecretStoreError.unexpectedStatus(status)
        }
    }
}
