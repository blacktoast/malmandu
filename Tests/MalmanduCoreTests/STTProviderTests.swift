import Testing
import Foundation
@testable import MalmanduCore

@Suite("STTProvider Tests")
struct STTProviderTests {

    @Test("isRealtimeModel: stt-rt-v4 → true")
    func isRealtimeModelRTv4() {
        #expect(STTProvider.isRealtimeModel("stt-rt-v4") == true)
    }

    @Test("isRealtimeModel: stt-rt- prefix → true")
    func isRealtimeModelPrefix() {
        #expect(STTProvider.isRealtimeModel("stt-rt-v99") == true)
    }

    @Test("isRealtimeModel: stt-async-v4 → false")
    func isRealtimeModelAsync() {
        #expect(STTProvider.isRealtimeModel("stt-async-v4") == false)
    }

    @Test("isRealtimeModel: empty string → false")
    func isRealtimeModelEmpty() {
        #expect(STTProvider.isRealtimeModel("") == false)
    }

    @Test("isRealtimeModel: case sensitive — stt-RT-v4 → false")
    func isRealtimeModelCaseSensitive() {
        #expect(STTProvider.isRealtimeModel("stt-RT-v4") == false)
    }

    @Test("isRealtimeModel: stt-rt without dash → false")
    func isRealtimeModelNoDash() {
        #expect(STTProvider.isRealtimeModel("stt-rtv4") == false)
    }

    @Test("각 provider의 defaultModel이 models 목록에 존재한다")
    func defaultModelExistsInModels() {
        for provider in STTProvider.allCases {
            let modelIds = provider.models.map(\.id)
            #expect(modelIds.contains(provider.defaultModel),
                    "\(provider.displayName)의 defaultModel '\(provider.defaultModel)'가 models에 없음")
        }
    }

    @Test("각 provider의 models가 비어있지 않다")
    func modelsNotEmpty() {
        for provider in STTProvider.allCases {
            #expect(!provider.models.isEmpty, "\(provider.displayName)의 models가 비어있음")
        }
    }

    @Test("keychainAccount가 provider 간 중복되지 않는다")
    func keychainAccountsDistinct() {
        let accounts = STTProvider.allCases.map(\.keychainAccount)
        #expect(Set(accounts).count == accounts.count, "keychainAccount 중복 발견")
    }

    @Test("modelUserDefaultsKey가 provider 간 중복되지 않는다")
    func modelDefaultsKeysDistinct() {
        let keys = STTProvider.allCases.map(\.modelUserDefaultsKey)
        #expect(Set(keys).count == keys.count, "modelUserDefaultsKey 중복 발견")
    }

    @Test("STTModelInfo는 Identifiable이다")
    func modelInfoIdentifiable() {
        let model = STTModelInfo(id: "test", displayName: "Test")
        #expect(model.id == "test")
    }
}
