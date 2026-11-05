import AVFoundation
import Foundation

/// Reads an audio file (mp3, wav, m4a, aiff…) into the form the `VoiceMixer` plays.
enum AudioDecoder {
    /// A soundboard is for short sounds; the longest one is kept in memory, decoded.
    static let maxDuration: TimeInterval = 30

    enum DecodeError: LocalizedError, Equatable {
        case unreadable
        case tooLong(seconds: Int)
        case emptyTrim

        var errorDescription: String? {
            switch self {
            case .unreadable: L.errAudioUnreadable.string
            case .emptyTrim: L.errTrimEmpty.string
            case .tooLong(let seconds):
                L.errSoundTooLong.formatted(String(seconds), String(Int(AudioDecoder.maxDuration)))
            }
        }
    }

    static func duration(of url: URL) throws -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else {
            throw DecodeError.unreadable
        }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    /// The file as interleaved stereo at `sampleRate` (a mono file is played in both channels), from `trimStart` to
    /// `trimEnd` seconds (nil: to the end), brought to a common volume when `normalize` is set.
    static func decode(
        url: URL, sampleRate: Double, trimStart: Double = 0, trimEnd: Double? = nil, normalize: Bool = false
    ) throws -> SoundClip {
        let seconds = try duration(of: url)
        guard seconds <= maxDuration else { throw DecodeError.tooLong(seconds: Int(seconds.rounded(.up))) }

        guard let file = try? AVAudioFile(forReading: url), file.length > 0,
            let source = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
            (try? file.read(into: source)) != nil,
            let target = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false),
            let converter = AVAudioConverter(from: file.processingFormat, to: target)
        else { throw DecodeError.unreadable }

        let capacity = AVAudioFrameCount(Double(file.length) * sampleRate / file.processingFormat.sampleRate) + 4096
        guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw DecodeError.unreadable
        }

        var delivered = false
        var failure: NSError?
        converter.convert(to: converted, error: &failure) { _, status in
            if delivered {
                status.pointee = .endOfStream
                return nil
            }
            delivered = true
            status.pointee = .haveData
            return source
        }
        guard failure == nil, let channels = converted.floatChannelData, converted.frameLength > 0 else {
            throw DecodeError.unreadable
        }

        let frames = Int(converted.frameLength)
        var samples = [Float](repeating: 0, count: frames * 2)
        for frame in 0..<frames {
            samples[frame * 2] = channels[0][frame]
            samples[frame * 2 + 1] = channels[1][frame]
        }
        return try SoundClip(samples: samples).processed(
            sampleRate: sampleRate, trimStart: trimStart, trimEnd: trimEnd, normalize: normalize)
    }
}
