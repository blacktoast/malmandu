import Testing
import Foundation
@testable import MalmanduCore

@Suite("TextPolisher Tests")
struct TextPolisherTests {

    @Test("API 키 없으면 원본 텍스트를 그대로 반환한다")
    func noApiKeyReturnsRawText() async {
        let polisher = TextPolisher(apiKeyProvider: { nil })
        let result = try? await polisher.polish("이것은 테스트 문장입니다", language: "ko")
        #expect(result == "이것은 테스트 문장입니다")
    }

    @Test("빈 문자열은 그대로 반환한다")
    func emptyStringReturnsEmpty() async {
        let polisher = TextPolisher(apiKeyProvider: { "fake-key" })
        let result = try? await polisher.polish("", language: "ko")
        #expect(result == "")
    }

    @Test("공백만 있는 문자열은 원본을 반환한다")
    func whitespaceOnlyReturnsRawText() async {
        let polisher = TextPolisher(apiKeyProvider: { "fake-key" })
        let result = try? await polisher.polish("   \n  ", language: "ko")
        #expect(result == "   \n  ")
    }

    @Test("10자 미만 텍스트는 LLM 없이 trimmed 반환한다")
    func shortTextSkipsLLM() async {
        let polisher = TextPolisher(apiKeyProvider: { "fake-key" })
        let result = try? await polisher.polish("안녕", language: "ko")
        #expect(result == "안녕")
    }

    @Test("9자는 건너뛰고 10자는 API 호출 시도한다")
    func boundaryAt10Chars() async {
        let polisher = TextPolisher(apiKeyProvider: { "fake-key" })
        // 9자: 건너뜀
        let short = try? await polisher.polish("123456789", language: "ko")
        #expect(short == "123456789")
        // 10자: API 호출 시도 → 실패 → 원본 반환 (fake key이므로)
        let long = try? await polisher.polish("1234567890", language: "ko")
        #expect(long == "1234567890")
    }
}
