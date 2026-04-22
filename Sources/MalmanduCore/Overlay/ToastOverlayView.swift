import SwiftUI

/// 토스트 알림 오버레이 (에러/안내 메시지)
public struct ToastOverlayView: View {
    let icon: String
    let message: String
    let submessage: String?

    public init(icon: String = "exclamationmark.triangle.fill", message: String, submessage: String? = nil) {
        self.icon = icon
        self.message = message
        self.submessage = submessage
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)

                if let submessage {
                    Text(submessage)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
    }
}
