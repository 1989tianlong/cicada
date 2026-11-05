import AVFoundation
import AudioToolbox
import CoreAudio

/// The talk key's microphone with the system's echo cancellation (VoiceProcessingIO): with speakers
/// on, the meeting's own voices reach the mic, and Cicada would translate them and speak them back
/// into the room. Measured with a clip on the MacBook speakers at 60 %: 38–39 of 43 words recognized
/// from the bare mic, none through this.
///
/// The raw unit, because AVAudioEngine's voice processing fails ('bfmt') when the default input is
/// the virtual mic, which 同声传译 makes it. Making the unit takes ~1.8 s, so it is made ahead and
/// only started (~40 ms) and stopped per press; made but stopped, it doesn't hold the mic open, but
/// it does starve AVAudioEngine's input on the same mic (−56 dB peaks): it is let go of before the
/// plain mic is used.
/// AGC is off (it lifts the room's noise with the voice, which recognition likes less), and other
/// audio's ducking is set to its minimum: the meeting must stay audible while you talk.
final class VoiceMic: @unchecked Sendable {
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    private let queue = DispatchQueue(label: "com.wquguru.cicada.voicemic")
    private let lock = NSLock()
    private var unit: AudioUnit?
    /// The devices the unit was made for: another mic or output means making it again.
    private var builtFor: (input: AudioObjectID, output: AudioObjectID)?
    private var building = false
    private var running = false
    private var onAudio: ((AVAudioPCMBuffer) -> Void)?
    private var scratch = [Float](repeating: 0, count: 8192)
    /// After a unit is made or let go of: any output engine already running in this process is
    /// silent from then on (measured: playing into BlackHole stops), and must be made anew.
    var onUnitChanged: (() -> Void)?

    deinit {
        if let unit {
            AudioOutputUnitStop(unit)
            AudioComponentInstanceDispose(unit)
        }
    }

    /// Makes the unit for `input` and the current output in the background, unless it already is.
    func prepare(input: AudioObjectID) {
        guard let output = SystemAudioTap.defaultOutputDevice() else { return }
        lock.lock()
        let ready = builtFor.map { $0 == (input, output) } ?? false
        if ready || building { lock.unlock(); return }
        building = true
        lock.unlock()
        queue.async { [self] in
            let t0 = Date()
            let made = make(input: input, output: output)
            lock.withLock {
                if let old = unit, !running { AudioComponentInstanceDispose(old); unit = nil; builtFor = nil }
                if let made, unit == nil { unit = made; builtFor = (input, output) } else if let made { AudioComponentInstanceDispose(made) }
                building = false
            }
            debugLog(String(format: "voice mic: %@ in %.1f s (input %u, output %u)", made == nil ? "failed" : "ready",
                            Date().timeIntervalSince(t0), input, output))
            onUnitChanged?()
        }
    }

    /// Starts hearing `input` if the unit is ready for it and the current output; otherwise false,
    /// and the caller uses the plain mic for this press, then `prepare`s for the next.
    func start(input: AudioObjectID, onAudio: @escaping (AVAudioPCMBuffer) -> Void) -> Bool {
        guard let output = SystemAudioTap.defaultOutputDevice() else { return false }
        lock.lock()
        guard let unit, let b = builtFor, b == (input, output), !running else {
            let busy = running
            lock.unlock()
            // Made again after the press (`prepare`), not during it: a new unit would starve the plain mic.
            if !busy { release() }
            return false
        }
        self.onAudio = onAudio
        running = true
        lock.unlock()
        let status = AudioOutputUnitStart(unit)
        if status != noErr {
            debugLog("voice mic: start failed \(status)")
            lock.withLock { running = false; self.onAudio = nil; builtFor = nil }
            return false
        }
        return true
    }

    /// Lets go of the unit (not while it runs), so the plain mic hears again.
    func release() {
        let old: AudioUnit? = lock.withLock {
            guard !running, let u = unit else { return nil }
            unit = nil
            builtFor = nil
            return u
        }
        if let old {
            AudioComponentInstanceDispose(old)
            debugLog("voice mic: released")
            onUnitChanged?()
        }
    }

    func stop() {
        lock.lock()
        guard running, let unit else { lock.unlock(); return }
        running = false
        lock.unlock()
        AudioOutputUnitStop(unit)
        lock.withLock { onAudio = nil }
    }

    private func make(input: AudioObjectID, output: AudioObjectID) -> AudioUnit? {
        var desc = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_VoiceProcessingIO,
                                             componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        guard let comp = AudioComponentFindNext(nil, &desc) else { return nil }
        var made: AudioUnit?
        guard AudioComponentInstanceNew(comp, &made) == noErr, let u = made else { return nil }
        func set<T>(_ property: AudioUnitPropertyID, _ scope: AudioUnitScope, _ element: AudioUnitElement, _ value: T) -> Bool {
            let status = withUnsafeBytes(of: value) {
                AudioUnitSetProperty(u, property, scope, element, $0.baseAddress, UInt32($0.count))
            }
            if status != noErr { debugLog("voice mic: property \(property) failed \(status)") }
            return status == noErr
        }
        // Element 1 is the mic, element 0 the output the echo is heard against.
        var ok = set(kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 1, input)
            && set(kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, output)
        _ = set(kAUVoiceIOProperty_VoiceProcessingEnableAGC, kAudioUnitScope_Global, 0, UInt32(0))
        _ = set(kAUVoiceIOProperty_OtherAudioDuckingConfiguration, kAudioUnitScope_Global, 0,
                AUVoiceIOOtherAudioDuckingConfiguration(mEnableAdvancedDucking: false, mDuckingLevel: .min))
        let asbd = Self.format.streamDescription.pointee
        ok = ok && set(kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, asbd)
            && set(kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, asbd)
        ok = ok && set(kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
                       AURenderCallbackStruct(inputProc: { ref, flags, ts, _, frames, _ in
                           Unmanaged<VoiceMic>.fromOpaque(ref).takeUnretainedValue().render(flags, ts, frames)
                       }, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()))
        if ok, AudioUnitInitialize(u) == noErr { return u }
        AudioComponentInstanceDispose(u)
        return nil
    }

    /// On the real-time thread, as `SystemAudioTap.render`.
    private func render(_ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, _ ts: UnsafePointer<AudioTimeStamp>,
                        _ frames: UInt32) -> OSStatus {
        guard let unit, frames > 0, Int(frames) <= scratch.count else { return noErr }
        let status = scratch.withUnsafeMutableBufferPointer { p -> OSStatus in
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: frames * 4, mData: p.baseAddress))
            return AudioUnitRender(unit, flags, ts, 1, frames, &list)
        }
        guard status == noErr, let onAudio, let out = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: frames),
              let dst = out.floatChannelData?[0] else { return status }
        out.frameLength = frames
        scratch.withUnsafeBufferPointer { dst.update(from: $0.baseAddress!, count: Int(frames)) }
        onAudio(out)
        return noErr
    }
}
