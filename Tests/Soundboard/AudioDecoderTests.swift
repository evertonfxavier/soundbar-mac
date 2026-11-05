import Foundation
import Testing

@Suite("AudioDecoder")
struct AudioDecoderTests {
    private func makeFolder() -> URL { TestAudio.temporaryDirectory() }

    @Test("a mono file is resampled to the rate asked, and played in both channels")
    func monoToStereoResampled() throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try TestAudio.writeWAV(
            to: folder.appendingPathComponent("a.wav"), sampleRate: 8000, seconds: 0.5, values: [0.5])

        let clip = try AudioDecoder.decode(url: url, sampleRate: 48_000)

        #expect(abs(clip.frames - 24_000) < 200)
        let middle = clip.frames / 2
        #expect(abs(clip.samples[middle * 2] - 0.5) < 0.02)
        #expect(abs(clip.samples[middle * 2 + 1] - 0.5) < 0.02)
    }

    @Test("a stereo file keeps its two sides apart")
    func stereoKeepsSides() throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try TestAudio.writeWAV(
            to: folder.appendingPathComponent("s.wav"), sampleRate: 48_000, seconds: 0.2, values: [0.5, -0.25])

        let clip = try AudioDecoder.decode(url: url, sampleRate: 48_000)

        let middle = clip.frames / 2
        #expect(abs(clip.samples[middle * 2] - 0.5) < 0.01)
        #expect(abs(clip.samples[middle * 2 + 1] + 0.25) < 0.01)
    }

    @Test("it tells the duration of a file")
    func duration() throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try TestAudio.writeWAV(to: folder.appendingPathComponent("d.wav"), sampleRate: 8000, seconds: 2)
        #expect(abs(try AudioDecoder.duration(of: url) - 2) < 0.01)
    }

    @Test("a sound longer than the limit is refused")
    func tooLong() throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try TestAudio.writeWAV(
            to: folder.appendingPathComponent("long.wav"), sampleRate: 8000, seconds: AudioDecoder.maxDuration + 1)
        #expect(throws: AudioDecoder.DecodeError.tooLong(seconds: Int(AudioDecoder.maxDuration) + 1)) {
            try AudioDecoder.decode(url: url, sampleRate: 48_000)
        }
    }

    @Test("a file that is not audio is refused")
    func notAudio() throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("notes.mp3")
        try Data("this is not audio".utf8).write(to: url)
        #expect(throws: AudioDecoder.DecodeError.unreadable) { try AudioDecoder.decode(url: url, sampleRate: 48_000) }
        #expect(throws: AudioDecoder.DecodeError.unreadable) { try AudioDecoder.duration(of: url) }
    }

    @Test("the errors are readable, in the language of the app, and say the numbers")
    func messages() {
        #expect(AudioDecoder.DecodeError.unreadable.errorDescription == L.errAudioUnreadable.string)
        let tooLong = AudioDecoder.DecodeError.tooLong(seconds: 45).errorDescription
        #expect(tooLong?.contains("45") == true)
        #expect(tooLong?.contains("\(Int(AudioDecoder.maxDuration))") == true)
    }
}
