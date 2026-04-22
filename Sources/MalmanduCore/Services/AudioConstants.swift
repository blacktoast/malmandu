import AVFoundation

enum AudioConstants {
    /// M4A 녹음/저장용 오디오 설정 (16kHz, 모노, AAC High)
    nonisolated(unsafe) static let m4aSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]
}
