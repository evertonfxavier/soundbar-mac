import CoreAudio
import Foundation

/// Gain shared between the main thread (writer) and the realtime IO thread (reader).
final class GainState: @unchecked Sendable {
    var target: Float
    var current: Float
    init(_ g: Float) { target = g; current = g }
}

/// Intercepts the audio of a set of processes with a Core Audio process tap,
/// mutes the original output, and replays it with a gain applied to an output device.
///
/// Pipeline: [processes] -> CATapDescription (mutedWhenTapped)
///           -> private aggregate device (output device + tap)
///           -> IOProc: tap input * gain -> device output
final class AppTap {
    let objectIDs: Set<AudioObjectID>
    let outputUID: String

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let gain: GainState
    private let queue = DispatchQueue(label: "soundbar.tap", qos: .userInteractive)

    init(objectIDs: [AudioObjectID], outputUID: String, gain initialGain: Float, label: String) throws {
        self.objectIDs = Set(objectIDs)
        self.outputUID = outputUID
        self.gain = GainState(initialGain)

        do {
            try start(objectIDs: objectIDs, label: label)
        } catch {
            stop()
            throw error
        }
    }

    deinit { stop() }

    func setGain(_ g: Float) { gain.target = g }

    private func start(objectIDs: [AudioObjectID], label: String) throws {
        // 1. Process tap. mutedWhenTapped silences the app's own output while we are reading the tap.
        let desc = CATapDescription(stereoMixdownOfProcesses: objectIDs)
        desc.uuid = UUID()
        desc.name = "SoundBar \(label)"
        desc.isPrivate = true
        desc.muteBehavior = .mutedWhenTapped
        try check(AudioHardwareCreateProcessTap(desc, &tapID), "AudioHardwareCreateProcessTap")

        let tapUID = CA.getString(tapID, kAudioTapPropertyUID) ?? desc.uuid.uuidString

        // 2. Aggregate device: real output device + the tap as an input.
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SoundBar \(label)",
            kAudioAggregateDeviceUIDKey: "soundbar-\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapUID,
                ]
            ],
        ]
        try check(
            AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggregateID),
            "AudioHardwareCreateAggregateDevice")

        // Input streams of the aggregate = the output device's own input streams (e.g. AirPods mic)
        // followed by the tap stream. Skip the device's mic so we never open it.
        let deviceInputStreams = CA.device(forUID: outputUID).map { CA.streamCount($0, input: true) } ?? 0
        let totalInputStreams = CA.streamCount(aggregateID, input: true)

        // 3. IOProc that copies tap -> output with gain.
        let gain = self.gain
        let tapStart = deviceInputStreams
        try check(
            AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, inInput, _, outOutput, _ in
                let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInput))
                let output = UnsafeMutableAudioBufferListPointer(outOutput)
                AppTap.render(input: input, inputStart: tapStart, output: output, gain: gain)
            }, "AudioDeviceCreateIOProcIDWithBlock")

        if deviceInputStreams > 0, totalInputStreams > deviceInputStreams, let procID {
            disableInputStreams(count: deviceInputStreams, of: totalInputStreams, procID: procID)
        }

        try check(AudioDeviceStart(aggregateID, procID), "AudioDeviceStart")
    }

    /// Tells the HAL our IOProc doesn't use the first `count` input streams, so the
    /// output device's microphone (AirPods, USB headsets) is not activated.
    private func disableInputStreams(count: Int, of total: Int, procID: AudioDeviceIOProcID) {
        let headerSize = MemoryLayout<UnsafeMutableRawPointer>.size + MemoryLayout<UInt32>.size
        let size = headerSize + total * MemoryLayout<UInt32>.size
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer { raw.deallocate() }
        raw.storeBytes(of: unsafeBitCast(procID, to: UnsafeMutableRawPointer.self), as: UnsafeMutableRawPointer.self)
        raw.storeBytes(of: UInt32(total), toByteOffset: MemoryLayout<UnsafeMutableRawPointer>.size, as: UInt32.self)
        for i in 0..<total {
            let on: UInt32 = i < count ? 0 : 1
            raw.storeBytes(of: on, toByteOffset: headerSize + i * MemoryLayout<UInt32>.size, as: UInt32.self)
        }
        var addr = CA.address(kAudioDevicePropertyIOProcStreamUsage, scope: kAudioObjectPropertyScopeInput)
        AudioObjectSetPropertyData(aggregateID, &addr, 0, nil, UInt32(size), raw)
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        procID = nil
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    // MARK: - Realtime render (no allocations, no locks)

    private struct Channel {
        let ptr: UnsafeMutablePointer<Float>
        let offset: Int
        let stride: Int
        let frames: Int
    }

    @inline(__always)
    private static func channel(_ list: UnsafeMutableAudioBufferListPointer, from start: Int, _ index: Int) -> Channel?
    {
        var c = index
        var i = start
        while i < list.count {
            let b = list[i]
            let n = Int(b.mNumberChannels)
            if c < n {
                guard let data = b.mData, n > 0 else { return nil }
                let frames = Int(b.mDataByteSize) / (MemoryLayout<Float>.size * n)
                return Channel(ptr: data.assumingMemoryBound(to: Float.self), offset: c, stride: n, frames: frames)
            }
            c -= n
            i += 1
        }
        return nil
    }

    @inline(__always)
    private static func channelCount(_ list: UnsafeMutableAudioBufferListPointer, from start: Int) -> Int {
        var n = 0
        var i = start
        while i < list.count { n += Int(list[i].mNumberChannels); i += 1 }
        return n
    }

    static func render(
        input: UnsafeMutableAudioBufferListPointer, inputStart: Int,
        output: UnsafeMutableAudioBufferListPointer, gain: GainState
    ) {
        for b in output { if let d = b.mData { memset(d, 0, Int(b.mDataByteSize)) } }

        let inCh = channelCount(input, from: inputStart)
        let outCh = channelCount(output, from: 0)
        guard inCh > 0, outCh > 0 else { return }

        let start = gain.current
        let target = gain.target

        if outCh == 1 {
            guard let o = channel(output, from: 0, 0), let l = channel(input, from: inputStart, 0) else { return }
            let r = inCh > 1 ? channel(input, from: inputStart, 1) : nil
            let frames = min(o.frames, l.frames, r?.frames ?? .max)
            for f in 0..<frames {
                let g = start + (target - start) * Float(f) / Float(max(frames, 1))
                var s = l.ptr[f * l.stride + l.offset]
                if let r { s = (s + r.ptr[f * r.stride + r.offset]) * 0.5 }
                o.ptr[f * o.stride + o.offset] = max(-1, min(1, s * g))
            }
        } else {
            for c in 0..<min(outCh, inCh) {
                guard let o = channel(output, from: 0, c), let i = channel(input, from: inputStart, c) else { continue }
                let frames = min(o.frames, i.frames)
                for f in 0..<frames {
                    let g = start + (target - start) * Float(f) / Float(max(frames, 1))
                    o.ptr[f * o.stride + o.offset] = max(-1, min(1, i.ptr[f * i.stride + i.offset] * g))
                }
            }
        }
        gain.current = target
    }
}
