import AVFoundation
import CoreAudio
import Foundation
import Testing
@testable import Cicada

private final class MicFrames: RecognitionStream, @unchecked Sendable {
    let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
    var results: AsyncThrowingStream<Recognition.Piece, Error> { AsyncThrowingStream { $0.finish() } }
    private let lock = NSLock()
    private var frames = 0
    var count: Int { lock.withLock { frames } }
    func append(_ buffer: AVAudioPCMBuffer) { lock.withLock { frames += Int(buffer.frameLength) } }
    func finalize(through seconds: Double) async throws {}
    func finish() async {}
    func cancel() async {}
}

@MainActor @Suite struct SpeakMicTests {
    // Requires microphone permission and a virtual system input with a different format from
    // the real mic. Opt in locally: CI has neither these devices nor microphone permission.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CICADA_TEST_MIC"] == "1"))
    func repeatedPressesCaptureFromTheRealMic() async throws {
        let original = try #require(AudioDevices.defaultInput)
        try #require(original.isVirtualMic, "Select BlackHole as the system input before this hardware test")
        // A continuity microphone may be listed first: hardware tests must only open this Mac's mic.
        let device = try #require(AudioDevices.inputs().first {
            AudioDevices.transport($0.id) == kAudioDeviceTransportTypeBuiltIn
        })
        let frames = MicFrames()
        let previousHost = Recognition.host
        Recognition.host = { _, _ in frames }
        defer { Recognition.host = previousHost }
        let speak = SpeakEngine(settings: AppSettings(), voiceMic: VoiceMic())
        speak.inputDevice = { device }
        speak.probe = SpeakProbe()
        defer { speak.pressCancelled() }
        await speak.prepare()
        for _ in 0..<3 {
            let before = frames.count
            speak.pressBegan()
            try #require(speak.phase == .listening)
            try await Task.sleep(for: .milliseconds(500))
            // Cancel rather than release: this regression test must never translate or play audio.
            speak.pressCancelled()
            #expect(frames.count > before)
            #expect(speak.phase == .idle)
        }
        #expect(AudioDevices.defaultInput?.uid == original.uid)
    }
}
