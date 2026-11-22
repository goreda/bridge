// E1Headless native-rate output of decoded s16 interleaved PCM.
// Real default-output AudioUnit callback evidence, no resampling or fake clock.
#if canImport(AppKit) && canImport(CoreAudio)
import Foundation
import AudioToolbox

struct E1AudioReceipt: Sendable {
    let suppliedBytes: Int
    let pushedBytes: Int
    let consumedBytes: Int
    let residualBytes: Int
    let overrunBytes: Int
    let closeMs: Double
    let producerFailed: Bool
    let sampleRate: Double
    let channels: Int
    let callbacks: Int
}

private final class E1PCMContext: @unchecked Sendable {
    let pcm: [UInt8]
    let bytesPerFrame: Int
    let lock = NSLock()
    var offset = 0
    var callbacks = 0
    var failed = false
    init(pcm: [UInt8], channels: Int) { self.pcm = pcm; bytesPerFrame = channels * 2 }
    func render(_ frames: UInt32, _ data: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
        guard let data else { return noErr }
        lock.lock(); defer { lock.unlock() }
        callbacks += 1
        let wanted = Int(frames) * bytesPerFrame
        let buffers = UnsafeMutableAudioBufferListPointer(data)
        // The configured format is one interleaved stereo buffer. Refuse a
        // different topology before consuming bytes rather than count twice.
        guard buffers.count == 1, let buffer = buffers.first,
              buffer.mNumberChannels == 2, let out = buffer.mData,
              Int(buffer.mDataByteSize) >= wanted else {
            failed = true
            for buffer in buffers {
                if let out = buffer.mData { memset(out, 0, Int(buffer.mDataByteSize)) }
            }
            return kAudio_ParamError
        }
        memset(out, 0, Int(buffer.mDataByteSize))
        let n = min(wanted, pcm.count - offset)
        if n > 0 {
            _ = pcm.withUnsafeBytes { raw in memcpy(out, raw.baseAddress!.advanced(by: offset), n) }
            offset += n
        }
        return noErr
    }
    func snapshot() -> (bytes: Int, callbacks: Int, failed: Bool) {
        lock.lock(); defer { lock.unlock() }; return (offset, callbacks, failed)
    }
}
private var e1FailedContexts: [E1PCMContext] = []
private let e1RetentionLock = NSLock()
private func e1RetainFailed(_ context: E1PCMContext) {
    e1RetentionLock.lock(); defer { e1RetentionLock.unlock() }; e1FailedContexts.append(context)
}
private let e1RenderCallback: AURenderCallback = { refcon, _, _, _, frames, data in
    return Unmanaged<E1PCMContext>.fromOpaque(refcon).takeUnretainedValue().render(frames, data)
}

final class E1AudioOut: @unchecked Sendable {
    private var unit: AudioUnit?
    private var context: E1PCMContext?
    private var rate = 44100.0
    private var channelCount = 2
    private var closed: E1AudioReceipt?
    init() throws {}
    var consumedBytes: Int { context?.snapshot().bytes ?? 0 }
    var mediaTime: Double { Double(consumedBytes) / (rate * Double(channelCount * 2)) }
    var queuedBytes: Int { max(0, (context?.pcm.count ?? 0) - consumedBytes) }
    private func check(_ status: OSStatus, _ stage: String) throws {
        if status != noErr { throw NSError(domain: "E1AudioOut", code: Int(status), userInfo: [NSLocalizedDescriptionKey: stage]) }
    }
    func start(pcm: [UInt8], sampleRate: Double = 44100, channels: Int = 2) throws {
        guard unit == nil, context == nil, closed == nil, !pcm.isEmpty,
              channels == 2, sampleRate.isFinite, sampleRate >= 8000, sampleRate <= 192000,
              pcm.count % (channels * 2) == 0 else {
            throw NSError(domain: "E1AudioOut", code: 2, userInfo: [NSLocalizedDescriptionKey: "fresh whole s16 stereo PCM and explicit valid rate required"])
        }
        var desc = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_DefaultOutput, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &desc) else { throw NSError(domain: "E1AudioOut", code: 3) }
        var candidate: AudioUnit?
        try check(AudioComponentInstanceNew(component, &candidate), "create default output")
        guard let u = candidate else { throw NSError(domain: "E1AudioOut", code: 4) }
        let c = E1PCMContext(pcm: pcm, channels: channels)
        do {
            var fmt = AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                mBytesPerPacket: UInt32(channels * 2), mFramesPerPacket: 1,
                mBytesPerFrame: UInt32(channels * 2), mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 16, mReserved: 0)
            try check(AudioUnitSetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &fmt, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)), "set native PCM rate")
            var callback = AURenderCallbackStruct(inputProc: e1RenderCallback, inputProcRefCon: Unmanaged.passUnretained(c).toOpaque())
            try check(AudioUnitSetProperty(u, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "set callback")
            try check(AudioUnitInitialize(u), "initialize output")
            context = c; rate = sampleRate; channelCount = channels; unit = u
            try check(AudioOutputUnitStart(u), "start output")
        } catch {
            AudioOutputUnitStop(u); AudioUnitUninitialize(u); AudioComponentInstanceDispose(u)
            unit = nil; context = nil; throw error
        }
    }
    func waitUntilConsumed(timeoutSeconds: Double = 12) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeoutSeconds
        while queuedBytes > 0 {
            if Task.isCancelled || ProcessInfo.processInfo.systemUptime >= deadline { return false }
            do { try await Task.sleep(nanoseconds: 2_000_000) } catch { return false }
        }
        return consumedBytes > 0
    }
    func close() async -> E1AudioReceipt {
        if let closed { return closed }
        let t0 = ProcessInfo.processInfo.systemUptime
        // AudioOutputUnitStop synchronously joins the render callback before
        // context is released. The context remains retained through disposal.
        var stopOK = true
        if let u = unit {
            stopOK = AudioOutputUnitStop(u) == noErr
            if stopOK { stopOK = AudioUnitUninitialize(u) == noErr }
            if stopOK { stopOK = AudioComponentInstanceDispose(u) == noErr }
            if stopOK { unit = nil }
        }
        let s = context?.snapshot() ?? (bytes: 0, callbacks: 0, failed: false)
        let supplied = context?.pcm.count ?? 0
        let r = E1AudioReceipt(suppliedBytes: supplied, pushedBytes: supplied, consumedBytes: s.bytes,
            residualBytes: max(0, supplied-s.bytes), overrunBytes: 0,
            closeMs: (ProcessInfo.processInfo.systemUptime-t0)*1000, producerFailed: !stopOK || s.failed,
            sampleRate: rate, channels: channelCount, callbacks: s.callbacks)
        // A failed stop retains the callback context for safety and fails evidence.
        if stopOK { context = nil }
        else if let context { e1RetainFailed(context) }
        closed = r; return r
    }
}
#endif
