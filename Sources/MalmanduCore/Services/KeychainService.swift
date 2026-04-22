import Foundation
import Security

/// Keychain 기반 API 키 저장 서비스
public final class KeychainService: KeychainServiceProtocol, Sendable {
    private let service: String
    private let account: String

    public init(service: String = "com.malmandu.api", account: String = "groq-api-key") {
        self.service = service
        self.account = account
    }

    public func save(apiKey: String) throws {
        // 기존 키 삭제
        try? deleteAPIKey()

        guard let data = apiKey.data(using: .utf8) else {
            throw AppError.apiKeyInvalid
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AppError.recordingFailed("Keychain save failed: \(status)")
        }
    }

    public func getAPIKey() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound { return nil }
            throw AppError.recordingFailed("Keychain read failed: \(status)")
        }

        return String(data: data, encoding: .utf8)
    }

    public func deleteAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.recordingFailed("Keychain delete failed: \(status)")
        }
    }
}
