import AVFoundation
import FluidAudio
import Foundation

/// FluidAudio Silero VAD 기반 무음 구간 제거 서비스
public final class AudioProcessor: AudioProcessorProtocol, @unchecked Sendable {
    private var vadManager: VadManager?

    public init() {}

    public func trimSilence(from audioURL: URL) async throws -> URL {
        // 1. VadManager lazy 초기화 (첫 호출 시 모델 다운로드)
        if vadManager == nil {
            vadManager = try await VadManager(config: VadConfig(defaultThreshold: 0.5))
        }

        // 2. 오디오를 16kHz mono Float32로 변환
        let samples = try AudioConverter().resampleAudioFile(path: audioURL.path)

        // 3. VAD로 음성 구간 추출
        var segConfig = VadSegmentationConfig.default
        segConfig.minSpeechDuration = 0.25  // 250ms 이상 음성만
        segConfig.minSilenceDuration = 0.3  // 300ms 이상 무음이면 자르기
        let segments = try await vadManager!.segmentSpeech(samples, config: segConfig)

        // 4. 음성 구간이 없으면 원본 반환 (빈 오디오 방지)
        guard !segments.isEmpty else { return audioURL }

        // 5. 음성 구간만 합쳐서 새 파일 생성
        var speechSamples: [Float] = []
        let sampleRate = 16000
        for segment in segments {
            let startSample = Int(segment.startTime * Double(sampleRate))
            let endSample = min(Int(segment.endTime * Double(sampleRate)), samples.count)
            if startSample < endSample {
                speechSamples.append(contentsOf: samples[startSample..<endSample])
            }
        }

        // 6. Float32 samples → M4A 파일로 저장
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("malmandu_vad_\(UUID().uuidString).m4a")
        try writeAudioFile(samples: speechSamples, to: outputURL)

        // 7. 원본 임시 파일 삭제
        try? FileManager.default.removeItem(at: audioURL)

        return outputURL
    }

    private func writeAudioFile(samples: [Float], to url: URL) throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000, channels: 1, interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        )!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        memcpy(buffer.floatChannelData![0], samples, samples.count * MemoryLayout<Float>.size)

        let file = try AVAudioFile(forWriting: url, settings: AudioConstants.m4aSettings)
        try file.write(from: buffer)
    }
}
