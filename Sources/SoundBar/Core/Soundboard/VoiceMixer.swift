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
