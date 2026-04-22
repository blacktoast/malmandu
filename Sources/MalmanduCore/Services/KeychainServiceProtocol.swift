import Foundation

/// Keychain 서비스 프로토콜
public protocol KeychainServiceProtocol: Sendable {
    func save(apiKey: String) throws
    func getAPIKey() throws -> String?
    func deleteAPIKey() throws
}
