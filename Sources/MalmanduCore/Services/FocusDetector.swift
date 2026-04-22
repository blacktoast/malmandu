import AppKit
import Foundation

/// 현재 포커스된 앱을 감지하고 도메인을 매핑
public final class FocusDetector: Sendable {

    public init() {}

    /// 현재 포커스된 앱의 번들 ID 반환
    public func frontmostAppBundleId() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// 현재 포커스된 앱 이름 반환
    public func frontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    /// 현재 앱이 텍스트 입력 가능한 상태인지 확인
    public func hasTextInputFocus() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        // 말만두 자체에 포커스 있으면 입력 불가로 판단
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return false }
        return true
    }

    /// 포커스된 앱을 기반으로 도메인/토픽 컨텍스트 생성
    public func appContext() -> AppDomainContext? {
        guard let bundleId = frontmostAppBundleId() else { return nil }
        return Self.domainMap[bundleId] ?? inferDomain(bundleId: bundleId)
    }

    // MARK: - 앱 → 도메인 매핑

    private static let domainMap: [String: AppDomainContext] = [
        // IDE / 코딩
        "com.microsoft.VSCode": AppDomainContext(domain: "Software Development", topic: "Coding"),
        "com.apple.dt.Xcode": AppDomainContext(domain: "Software Development", topic: "iOS/macOS Development"),
        "com.jetbrains.intellij": AppDomainContext(domain: "Software Development", topic: "Java Development"),
        "com.sublimetext.4": AppDomainContext(domain: "Software Development", topic: "Coding"),
        "dev.warp.Warp-Stable": AppDomainContext(domain: "Software Development", topic: "Terminal"),
        "com.apple.Terminal": AppDomainContext(domain: "Software Development", topic: "Terminal"),
        "com.googlecode.iterm2": AppDomainContext(domain: "Software Development", topic: "Terminal"),

        // 커뮤니케이션
        "com.tinyspeck.slackmacgap": AppDomainContext(domain: "Business Communication", topic: "Team Chat"),
        "ru.keepcoder.Telegram": AppDomainContext(domain: "Communication", topic: "Messaging"),
        "com.apple.MobileSMS": AppDomainContext(domain: "Communication", topic: "Messaging"),
        "com.discord.Discord": AppDomainContext(domain: "Communication", topic: "Community Chat"),
        "com.microsoft.teams2": AppDomainContext(domain: "Business Communication", topic: "Team Collaboration"),

        // 문서 작성
        "com.apple.iWork.Pages": AppDomainContext(domain: "Document Writing", topic: "Word Processing"),
        "com.microsoft.Word": AppDomainContext(domain: "Document Writing", topic: "Word Processing"),
        "com.google.Chrome": AppDomainContext(domain: "Web Browsing", topic: "General"),
        "com.apple.Safari": AppDomainContext(domain: "Web Browsing", topic: "General"),
        "md.obsidian": AppDomainContext(domain: "Note Taking", topic: "Knowledge Management"),
        "com.apple.Notes": AppDomainContext(domain: "Note Taking", topic: "Quick Notes"),
        "notion.id": AppDomainContext(domain: "Note Taking", topic: "Project Documentation"),

        // 이메일
        "com.apple.mail": AppDomainContext(domain: "Email", topic: "Business Email"),
        "com.microsoft.Outlook": AppDomainContext(domain: "Email", topic: "Business Email"),
    ]

    /// 번들 ID로 앱 활성화 ([계속] 버튼용)
    @discardableResult
    public func activateApp(bundleId: String) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else { return false }
        return app.activate(options: [.activateIgnoringOtherApps])
    }

    private func inferDomain(bundleId: String) -> AppDomainContext? {
        // 번들 ID 패턴으로 추론
        if bundleId.contains("terminal") || bundleId.contains("Terminal") {
            return AppDomainContext(domain: "Software Development", topic: "Terminal")
        }
        if bundleId.contains("mail") || bundleId.contains("Mail") {
            return AppDomainContext(domain: "Email", topic: "Email")
        }
        return nil
    }
}

/// 앱 기반 도메인 컨텍스트
public struct AppDomainContext: Sendable {
    public let domain: String
    public let topic: String

    public init(domain: String, topic: String) {
        self.domain = domain
        self.topic = topic
    }

    /// Soniox context.general 형식으로 변환
    public func toSonioxGeneral() -> [[String: String]] {
        [
            ["key": "domain", "value": domain],
            ["key": "topic", "value": topic],
        ]
    }
}
