import Testing
import Foundation
@testable import MalmanduCore

@Suite("DynamicSTTClient Tests")
struct DynamicSTTClientTests {

    @Test("clientProvider가 매 transcribe 호출마다 실행된다")
    func providerCalledPerInvocation() async throws {
        nonisolated(unsafe) var callCount = 0
        let mock = MockGroqAPIClient()
        mock.transcribeResult = "결과"

        let client = DynamicSTTClient {
            callCount += 1
            return mock
        }

        _ = try await client.transcribe(audioFileURL: URL(fileURLWithPath: "/tmp/test.m4a"),
                                         language: "ko", model: "test", prompt: nil)
        _ = try await client.transcribe(audioFileURL: URL(fileURLWithPath: "/tmp/test.m4a"),
                                         language: "ko", model: "test", prompt: nil)

        #expect(callCount == 2)
    }

    @Test("런타임에 provider를 전환하면 다른 클라이언트가 사용된다")
    func providerSwitchAtRuntime() async throws {
        let mock1 = MockGroqAPIClient()
        mock1.transcribeResult = "groq"
        let mock2 = MockGroqAPIClient()
        mock2.transcribeResult = "soniox"

        nonisolated(unsafe) var useMock1 = true
        let client = DynamicSTTClient {
            useMock1 ? mock1 : mock2
        }

        let url = URL(fileURLWithPath: "/tmp/test.m4a")
        let result1 = try await client.transcribe(audioFileURL: url, language: nil, model: "m", prompt: nil)
        #expect(result1 == "groq")

        useMock1 = false
        let result2 = try await client.transcribe(audioFileURL: url, language: nil, model: "m", prompt: nil)
        #expect(result2 == "soniox")
    }

    @Test("내부 클라이언트가 던진 에러가 그대로 전파된다")
    func errorPropagation() async {
        let mock = MockGroqAPIClient()
        mock.transcribeError = AppError.apiKeyMissing

        let client = DynamicSTTClient { mock }

        do {
            _ = try await client.transcribe(audioFileURL: URL(fileURLWithPath: "/tmp/test.m4a"),
                                             language: nil, model: "m", prompt: nil)
            #expect(Bool(false), "에러가 발생해야 함")
        } catch {
            #expect(error as? AppError == .apiKeyMissing)
        }
    }
}
