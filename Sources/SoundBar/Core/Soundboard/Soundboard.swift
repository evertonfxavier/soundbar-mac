import AVFoundation
import Combine
import Foundation

/// Where the soundboard stands.
enum SoundboardState: Equatable {
    /// The virtual microphone (BlackHole) is not installed: the sounds only play on the user's own speakers.
    case noDriver
    /// BlackHole is there, but no app is using it as its microphone.
    case idle
    /// An app uses BlackHole as its microphone: the sounds go into that call.
    case live
    case failed(String)
}

/// The soundboard: the user's sounds, playing them on the speakers and, while a call listens to the virtual
/// microphone, into the call too.
@MainActor
final class Soundboard: ObservableObject {
    @Published private(set) var sounds: [Sound]
    @Published private(set) var state: SoundboardState = .noDriver
    @Published var errorMessage: String?
    /// The real microphones the sounds can be mixed with, and the one the user chose (nil: the system's default).
    @Published private(set) var microphones: [SoundboardRouting.Device] = []
    @Published private(set) var chosenMicrophoneUID: String?

    let library: SoundLibrary

    private let voices = VoiceMixer()
    private var feed: MicFeed?
    private var feedKey: String?
    private var quietTicks = 0
    private var failedAt: Date?
    private var clips: [UUID: (rate: Double, clip: SoundClip)] = [:]
    private var players: [AVAudioPlayer] = []

    /// How many refreshes (about a second each) the feed stays up after the call stopped reading the virtual
    /// microphone, so a call that restarts its audio does not make the feed flap.
    private static let feedLinger = 3
    private static let microphoneKey = "soundboardMicrophoneUID"

    init(library: SoundLibrary = SoundLibrary(directory: SoundLibrary.defaultDirectory)) {
        self.library = library
        sounds = library.sounds
        chosenMicrophoneUID = UserDefaults.standard.string(forKey: Self.microphoneKey)
    }

    /// Chooses the microphone the sounds are mixed with; nil goes back to the system's default input.
    func chooseMicrophone(_ uid: String?) {
        chosenMicrophoneUID = uid
        if let uid {
            UserDefaults.standard.set(uid, forKey: Self.microphoneKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.microphoneKey)
        }
    }

    // MARK: - Playing

    func play(_ sound: Sound) {
        players.removeAll { !$0.isPlaying }
        do {
            let player = try AVAudioPlayer(contentsOf: library.audioURL(for: sound))
            player.volume = sound.volume
            player.play()
            players.append(player)
        } catch {
            errorMessage = "Não consegui tocar “\(sound.name)”."
            return
        }
        guard let feed else { return }
        do {
            voices.trigger(try clip(for: sound, rate: feed.sampleRate), gain: sound.volume)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopAll() {
        voices.stopAll()
        for player in players { player.stop() }
        players.removeAll()
    }

    private func clip(for sound: Sound, rate: Double) throws -> SoundClip {
        if let cached = clips[sound.id], cached.rate == rate { return cached.clip }
        let clip = try AudioDecoder.decode(url: library.audioURL(for: sound), sampleRate: rate)
        clips[sound.id] = (rate, clip)
        return clip
    }

    // MARK: - The library

    func add(_ draft: SoundLibrary.Draft) throws {
        try library.add(draft)
        sounds = library.sounds
    }

    func update(_ sound: Sound, with draft: SoundLibrary.Draft) throws {
        try library.update(sound.id, with: draft)
        clips[sound.id] = nil
        sounds = library.sounds
    }

    func remove(_ sound: Sound) {
        library.remove(sound.id)
        clips[sound.id] = nil
        sounds = library.sounds
    }

    // MARK: - The feed into the call

    /// Called about once a second with the audio processes: starts the feed when an app reads the virtual
    /// microphone, stops it a few seconds after that ends.
    func update(processes: [AudioProcess], devices: [SoundboardRouting.Device]) {
        let real = SoundboardRouting.realMicrophones(in: devices)
        if real != microphones { microphones = real }
        guard let virtual = SoundboardRouting.blackHole(in: devices) else {
            stopFeed()
            setState(.noDriver)
            return
        }

        if SoundboardRouting.shouldFeed(blackHoleUID: virtual.uid, processes: processes) {
            quietTicks = 0
        } else {
            quietTicks += 1
        }
        guard quietTicks < Self.feedLinger else {
            stopFeed()
            setState(.idle)
            return
        }

        guard
            let mic = SoundboardRouting.microphone(
                preferredUID: chosenMicrophoneUID, defaultInputUID: AudioDevices.defaultInputUID(), devices: devices)
        else {
            stopFeed()
            setState(.failed("Nenhum microfone encontrado."))
            return
        }

        let key = "\(mic.uid)|\(virtual.uid)"
        if feed == nil || feedKey != key {
            if let failedAt, Date().timeIntervalSince(failedAt) < 5 { return }
            stopFeed()
            do {
                feed = try MicFeed(micUID: mic.uid, virtualUID: virtual.uid, mixer: voices)
                feedKey = key
                failedAt = nil
            } catch {
                failedAt = Date()
                setState(.failed(error.localizedDescription))
                return
            }
        }
        setState(.live)
    }

    func shutdown() {
        stopAll()
        stopFeed()
    }

    private func stopFeed() {
        feed?.stop()
        feed = nil
        feedKey = nil
        voices.stopAll()
    }

    private func setState(_ new: SoundboardState) {
        if state != new { state = new }
    }
}
