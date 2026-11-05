import AVFoundation
import Foundation
import Testing

@Suite("Sound clips: trim, normalize, WAV")
struct SoundClipTests {
    /// 1 second at 100 Hz: frame i holds i/100 in both sides, so a position in the clip can be read off the value.
    private func ramp() -> SoundClip {
        var samples: [Float] = []
        for frame in 0..<100 { samples += [Float(frame) / 100, Float(frame) / 100] }
        return SoundClip(samples: samples)
    }

    @Test("the whole clip is kept when there is no trim")
    func noTrim() throws {
        let clip = try ramp().processed(sampleRate: 100, trimStart: 0, trimEnd: nil, normalize: false)
        #expect(clip.frames == 100)
    }

    @Test("a start and an end keep only what is between them")
    func trims() throws {
        let clip = try ramp().processed(sampleRate: 100, trimStart: 0.2, trimEnd: 0.5, normalize: false)
        #expect(clip.frames == 30)
        #expect(clip.samples.first == 0.2)
        #expect(abs((clip.samples.last ?? 0) - 0.49) < 0.0001)
    }

    @Test("an end past the clip, or a start before it, is kept inside the clip")
    func trimIsClamped() throws {
        let clip = try ramp().processed(sampleRate: 100, trimStart: -3, trimEnd: 99, normalize: false)
        #expect(clip.frames == 100)
    }

    @Test("nothing left is refused")
    func emptyTrim() {
        #expect(throws: AudioDecoder.DecodeError.emptyTrim) {
            try ramp().processed(sampleRate: 100, trimStart: 0.5, trimEnd: 0.5, normalize: false)
        }
        #expect(throws: AudioDecoder.DecodeError.emptyTrim) {
            try ramp().processed(sampleRate: 100, trimStart: 2, trimEnd: nil, normalize: false)
        }
    }

    @Test("normalizing brings a quiet clip up, without going past full scale")
    func normalizes() throws {
        let quiet = SoundClip(samples: [Float](repeating: 0.05, count: 200))
        let louder = try quiet.processed(sampleRate: 100, trimStart: 0, trimEnd: nil, normalize: true)
        #expect(abs((louder.samples.first ?? 0) - 0.1) < 0.001)
        #expect(louder.samples.allSatisfy { abs($0) <= 1 })
        // not asked: left alone
        #expect(
            try quiet.processed(sampleRate: 100, trimStart: 0, trimEnd: nil, normalize: false).samples == quiet.samples)
    }

    @Test("the trim applies before the level is measured")
    func normalizesTheTrimmedPart() throws {
        // 1 s of quiet then 1 s of loud: normalizing only the quiet half raises it to the target
        let samples = [Float](repeating: 0.02, count: 200) + [Float](repeating: 0.5, count: 200)
        let clip = try SoundClip(samples: samples).processed(sampleRate: 100, trimStart: 0, trimEnd: 1, normalize: true)
        #expect(abs((clip.samples.first ?? 0) - 0.1) < 0.001)
    }

    @Test("the WAV has the header of a 16-bit stereo file, and the samples")
    func wavHeader() throws {
        let data = SoundClip(samples: [0.5, -0.5, 1, -1]).wavData(sampleRate: 48_000)
        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: data[8..<16], as: UTF8.self) == "WAVEfmt ")
        #expect(data.count == 44 + 8)  // header + 2 frames x 2 channels x 2 bytes
        func u16(_ at: Int) -> UInt16 { UInt16(data[at]) | UInt16(data[at + 1]) << 8 }
        func u32(_ at: Int) -> UInt32 { UInt32(u16(at)) | UInt32(u16(at + 2)) << 16 }
        #expect(u16(20) == 1)  // PCM
        #expect(u16(22) == 2)  // channels
        #expect(u32(24) == 48_000)
        #expect(u16(34) == 16)
        #expect(u32(40) == 8)
        #expect(Int16(bitPattern: u16(44)) == Int16(0.5 * Float(Int16.max)))
        #expect(Int16(bitPattern: u16(50)) == -Int16.max)
    }

    @Test("a player can read what wavData wrote")
    func playerReadsIt() throws {
        let clip = SoundClip(samples: [Float](repeating: 0.25, count: 48_000 * 2))
        let player = try AVAudioPlayer(data: clip.wavData(sampleRate: 48_000), fileTypeHint: AVFileType.wav.rawValue)
        #expect(abs(player.duration - 1) < 0.01)
        #expect(player.numberOfChannels == 2)
    }

    @Test("decoding a file applies the trim and the normalizing")
    func decodeAppliesThem() throws {
        let folder = TestAudio.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try TestAudio.writeWAV(
            to: folder.appendingPathComponent("q.wav"), sampleRate: 8000, seconds: 2, values: [0.05])

        let whole = try AudioDecoder.decode(url: url, sampleRate: 8000)
        let part = try AudioDecoder.decode(
            url: url, sampleRate: 8000, trimStart: 0.5, trimEnd: 1.0, normalize: true)

        #expect(abs(part.frames - 4000) < 20)
        #expect(part.frames < whole.frames)
        let middle = part.samples[part.frames]  // a sample in the middle, left side
        #expect(abs(middle - 0.1) < 0.01)
    }
}
