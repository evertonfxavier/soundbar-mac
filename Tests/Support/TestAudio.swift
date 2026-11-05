import AVFoundation
import CoreAudio
import Foundation

/// Audio buffers the way the system hands them to an IOProc: a list of streams, each one interleaved.
final class TestStreams {
    let list: UnsafeMutableAudioBufferListPointer
    private let storage: [UnsafeMutablePointer<Float>]

    /// `streams[i]` holds the interleaved samples of stream `i`, which has `channels` channels.
    init(_ streams: [(channels: Int, samples: [Float])]) {
        list = AudioBufferList.allocate(maximumBuffers: max(streams.count, 1))
        list.count = streams.count
        var pointers: [UnsafeMutablePointer<Float>] = []
        for (index, stream) in streams.enumerated() {
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: max(stream.samples.count, 1))
            pointer.initialize(from: stream.samples, count: stream.samples.count)
            pointers.append(pointer)
            list[index] = AudioBuffer(
                mNumberChannels: UInt32(stream.channels),
                mDataByteSize: UInt32(stream.samples.count * MemoryLayout<Float>.size),
                mData: pointer)
        }
        storage = pointers
    }

    deinit {
        for pointer in storage { pointer.deallocate() }
        free(list.unsafeMutablePointer)
    }

    func samples(_ stream: Int = 0) -> [Float] {
        let buffer = list[stream]
        let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        return Array(UnsafeBufferPointer(start: buffer.mData?.assumingMemoryBound(to: Float.self), count: count))
    }
}

enum TestAudio {
    /// A folder that is removed by the caller.
    static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("soundbar-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes a 16-bit WAV in which every channel holds a constant: `values[c]` for channel `c`.
    @discardableResult
    static func writeWAV(
        to url: URL, sampleRate: Double = 8000, seconds: Double = 0.5, values: [Float] = [0.5]
    ) throws -> URL {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: values.count,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let frames = AVAudioFrameCount(sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)!
        buffer.frameLength = frames
        for (channel, value) in values.enumerated() {
            for frame in 0..<Int(frames) { buffer.floatChannelData![channel][frame] = value }
        }
        try file.write(from: buffer)
        return url
    }

    /// Interleaved stereo with a constant on each side.
    static func clip(frames: Int, left: Float, right: Float? = nil) -> SoundClip {
        var samples: [Float] = []
        for _ in 0..<frames { samples += [left, right ?? left] }
        return SoundClip(samples: samples)
    }
}

/// Waits until `condition` holds, looking every few milliseconds, for at most `timeout` seconds. For a result that
/// arrives asynchronously, so a test does not depend on a fixed sleep being long enough on a busy machine.
@MainActor
func eventually(timeout: TimeInterval = 3, _ condition: @MainActor () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return condition()
}
