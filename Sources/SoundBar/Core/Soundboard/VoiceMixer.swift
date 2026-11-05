import Foundation
import os

/// A sound decoded for the sample rate of the feed: interleaved stereo, Float32.
final class SoundClip: @unchecked Sendable {
    let samples: [Float]
    let frames: Int

    init(samples: [Float]) {
        self.samples = samples
        frames = samples.count / 2
    }

    /// The part from `trimStart` to `trimEnd` seconds (nil: to the end), scaled to a common volume when `normalize`
    /// is set. Throws `emptyTrim` when nothing is left.
    func processed(sampleRate: Double, trimStart: Double, trimEnd: Double?, normalize: Bool) throws -> SoundClip {
        let first = max(0, min(frames, Int((max(0, trimStart) * sampleRate).rounded())))
        let last = max(first, min(frames, trimEnd.map { Int((max(0, $0) * sampleRate).rounded()) } ?? frames))
        guard last > first else { throw AudioDecoder.DecodeError.emptyTrim }
        var part = (first == 0 && last == frames) ? samples : Array(samples[(first * 2)..<(last * 2)])
        if normalize {
            let gain = AudioAnalysis.normalizationGain(samples: part)
            if gain != 1 { part = part.map { max(-1, min(1, $0 * gain)) } }
        }
        return SoundClip(samples: part)
    }

    /// The clip as a 16-bit stereo WAV file in memory, for `AVAudioPlayer` (the speakers play what the call gets).
    func wavData(sampleRate: Double) -> Data {
        let dataSize = UInt32(samples.count * 2)
        var data = Data()
        func put32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func put16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8))
        put32(36 + dataSize)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        put32(16)
        put16(1)  // PCM
        put16(2)  // stereo
        put32(UInt32(sampleRate))
        put32(UInt32(sampleRate) * 4)
        put16(4)
        put16(16)
        data.append(contentsOf: Array("data".utf8))
        put32(dataSize)
        for sample in samples {
            put16(UInt16(bitPattern: Int16(max(-1, min(1, sample)) * Float(Int16.max))))
        }
        return data
    }
}

/// The sounds that are playing into the call. `trigger` starts one (from the main thread); `render` adds all of them,
/// one block at a time, to the buffer of the audio thread, so it never allocates and never waits: if the main thread
/// holds the lock at that very moment, that block simply goes without the sounds.
final class VoiceMixer: @unchecked Sendable {
    /// More than this at once and the oldest one is cut.
    static let maxVoices = 16

    private struct Voice {
        let clip: SoundClip
        let gain: Float
        var position = 0
    }

    private var voices: [Voice] = []
    /// Set from the main thread: the call hears nothing, neither the voice nor the sounds.
    private var callMuted = false
    /// What the audio thread last saw of `callMuted`; only that thread touches it.
    private var seenMuted = false
    private let lock: UnsafeMutablePointer<os_unfair_lock>

    init() {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
        voices.reserveCapacity(Self.maxVoices)
    }

    deinit {
        lock.deallocate()
    }

    var activeVoices: Int {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return voices.count
    }

    func trigger(_ clip: SoundClip, gain: Float) {
        guard clip.frames > 0 else { return }
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        if voices.count == Self.maxVoices { voices.removeFirst() }
        voices.append(Voice(clip: clip, gain: gain))
    }

    func setCallMuted(_ muted: Bool) {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        callMuted = muted
    }

    /// For the audio thread: whether the call is muted. If the main thread holds the lock at that moment, the answer
    /// of the previous block stands, so it never waits.
    func isCallMutedForRender() -> Bool {
        if os_unfair_lock_trylock(lock) {
            seenMuted = callMuted
            os_unfair_lock_unlock(lock)
        }
        return seenMuted
    }

    func stopAll() {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        voices.removeAll(keepingCapacity: true)
    }

    /// Adds the playing sounds to `buffer`, `frames` frames of interleaved samples with `channels` channels. The first
    /// two channels get the left and right of the sound (a mono buffer gets their average); the others are left alone.
    /// The sum is limited to full scale.
    func render(into buffer: UnsafeMutablePointer<Float>, frames: Int, channels: Int) {
        guard channels > 0, frames > 0, os_unfair_lock_trylock(lock) else { return }
        defer { os_unfair_lock_unlock(lock) }

        var index = 0
        while index < voices.count {
            let clip = voices[index].clip
            let gain = voices[index].gain
            let start = voices[index].position
            let count = min(frames, clip.frames - start)

            clip.samples.withUnsafeBufferPointer { source in
                for frame in 0..<count {
                    let left = source[(start + frame) * 2] * gain
                    let right = source[(start + frame) * 2 + 1] * gain
                    if channels == 1 {
                        buffer[frame] = Self.limited(buffer[frame] + (left + right) * 0.5)
                    } else {
                        buffer[frame * channels] = Self.limited(buffer[frame * channels] + left)
                        buffer[frame * channels + 1] = Self.limited(buffer[frame * channels + 1] + right)
                    }
                }
            }

            if start + count >= clip.frames {
                voices.remove(at: index)
            } else {
                voices[index].position = start + count
                index += 1
            }
        }
    }

    @inline(__always)
    private static func limited(_ sample: Float) -> Float {
        max(-1, min(1, sample))
    }
}
