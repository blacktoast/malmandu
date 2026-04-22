import Testing
import Foundation
@testable import MalmanduCore

// MARK: - KeychainServiceTests

@Suite("KeychainService Tests")
struct KeychainServiceTests {

    // 테스트마다 고유한 service 이름을 사용해 Keychain 충돌 방지
    private func makeService() -> KeychainService {
        KeychainService(
            service: "com.malmandu.test.\(UUID().uuidString)",
            account: "test-api-key"
        )
    }

    @Test("API 키를 저장하고 가져올 수 있다")
    func saveAndRetrieveAPIKey() throws {
        let service = makeService()
        let apiKey = "test-groq-api-key-12345"

        try service.save(apiKey: apiKey)
        let retrieved = try service.getAPIKey()

        #expect(retrieved == apiKey)
    }

    @Test("저장된 키가 없으면 nil을 반환한다")
    func getReturnsNilWhenNoKeyStored() throws {
        let service = makeService()

        let retrieved = try service.getAPIKey()

        #expect(retrieved == nil)
    }

    @Test("삭제하면 키가 제거된다")
    func deleteRemovesKey() throws {
        let service = makeService()
        try service.save(apiKey: "some-api-key")

        try service.deleteAPIKey()
        let retrieved = try service.getAPIKey()

        #expect(retrieved == nil)
    }

    @Test("저장이 기존 키를 덮어쓴다")
    func saveOverwritesExistingKey() throws {
        let service = makeService()
        try service.save(apiKey: "old-api-key")
        try service.save(apiKey: "new-api-key")

        let retrieved = try service.getAPIKey()

        #expect(retrieved == "new-api-key")
    }

    @Test("여러 번 저장/삭제 사이클이 올바르게 동작한다")
    func multipleSaveDeleteCyclesWorkCorrectly() throws {
        let service = makeService()

        // 1차 저장
        try service.save(apiKey: "key-1")
        #expect(try service.getAPIKey() == "key-1")

        // 1차 삭제
        try service.deleteAPIKey()
        #expect(try service.getAPIKey() == nil)

        // 2차 저장
        try service.save(apiKey: "key-2")
        #expect(try service.getAPIKey() == "key-2")

        // 2차 삭제
        try service.deleteAPIKey()
        #expect(try service.getAPIKey() == nil)

        // 3차 저장 (삭제 후 다시 저장 가능한지 확인)
        try service.save(apiKey: "key-3")
        #expect(try service.getAPIKey() == "key-3")
    }
}
