import Foundation
@testable import MalmanduCore

// MARK: - MockAudioRecorder

final class MockAudioRecorder: AudioRecorderProtocol, @unchecked Sendable {
    var startRecordingCalled = false
    var stopRecordingCalled = false
    var startRecordingError: Error? = nil
    var stopRecordingResult: URL = URL(fileURLWithPath: "/tmp/mock_recording.m4a")
    var stopRecordingError: Error? = nil
    private var _isRecording = false

    func startRecording() async throws {
        startRecordingCalled = true
        if let error = startRecordingError {
            throw error
        }
        _isRecording = true
    }

    func startRecordingWithStream(onAudioChunk: @escaping AudioChunkHandler) async throws {
        startRecordingCalled = true
        if let error = startRecordingError {
            throw error
        }
        _isRecording = true
    }

    func startRecordingWithStream(onAudioChunk: @escaping AudioChunkHandler, onAudioLevel: @escaping AudioLevelHandler) async throws {
        startRecordingCalled = true
        if let error = startRecordingError {
            throw error
        }
        _isRecording = true
    }

    func stopRecording() async throws -> URL {
        stopRecordingCalled = true
        _isRecording = false
        if let error = stopRecordingError {
            throw error
        }
        return stopRecordingResult
    }

    func isRecording() -> Bool {
        _isRecording
    }

    static func requestMicrophonePermission() async -> Bool {
        true
    }
}

// MARK: - MockGroqAPIClient

final class MockGroqAPIClient: GroqAPIClientProtocol, @unchecked Sendable {
    var transcribeCalled = false
    var transcribeResult: String = "mock transcription"
    var transcribeError: Error? = nil
    var lastAudioFileURL: URL? = nil
    var lastLanguage: String? = nil

    func transcribe(audioFileURL: URL, language: String?, model: String = "whisper-large-v3", prompt: String? = nil) async throws -> String {
        transcribeCalled = true
        lastAudioFileURL = audioFileURL
        lastLanguage = language
        if let error = transcribeError {
            throw error
        }
        return transcribeResult
    }
}

// MARK: - MockTextInjector

final class MockTextInjector: TextInjectorProtocol, @unchecked Sendable {
    var pasteTextCalled = false
    var lastPastedText: String? = nil
    var pasteResult: PasteResult = .success

    func pasteText(_ text: String) async -> PasteResult {
        pasteTextCalled = true
        lastPastedText = text
        return pasteResult
    }
}

// MARK: - MockAudioProcessor

final class MockAudioProcessor: AudioProcessorProtocol, @unchecked Sendable {
    var trimCalled = false
    var lastInputURL: URL? = nil

    func trimSilence(from audioURL: URL) async throws -> URL {
        trimCalled = true
        lastInputURL = audioURL
        return audioURL // mock은 원본 그대로 반환
    }
}

// MARK: - MockStreamingSTTClient

final class MockStreamingSTTClient: StreamingSTTServiceProtocol, @unchecked Sendable {
    var startStreamingCalled = false
    var finishStreamingCalled = false
    var sendAudioChunkCount = 0
    var finishStreamingResult: String = ""
    var finishStreamingError: Error? = nil
    var startStreamingError: Error? = nil

    private var onPartialResult: PartialResultHandler?
    private var onSegmentFinalized: SegmentFinalizedHandler?

    func startStreaming(
        language: String?,
        model: String,
        onPartialResult: @escaping PartialResultHandler,
        onSegmentFinalized: @escaping SegmentFinalizedHandler
    ) async throws {
        startStreamingCalled = true
        if let error = startStreamingError { throw error }
        self.onPartialResult = onPartialResult
        self.onSegmentFinalized = onSegmentFinalized
    }

    func sendAudioChunk(_ data: Data) async throws {
        sendAudioChunkCount += 1
    }

    func finishStreaming() async throws -> String {
        finishStreamingCalled = true
        if let error = finishStreamingError { throw error }
        return finishStreamingResult
    }

    func pauseStreaming() async {}
    func resumeStreaming() async {}
}

// MARK: - MockSoundService

final class MockSoundService: SoundServiceProtocol, @unchecked Sendable {
    var playedEvents: [SoundEvent] = []
    var soundEnabled: Bool = true

    func play(_ event: SoundEvent) {
        playedEvents.append(event)
    }
}
