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
    @Published private(set) var groups: [String] = []
    @Published private(set) var state: SoundboardState = .noDriver
    @Published var errorMessage: String?
    /// A neutral message, such as what an import did.
    @Published var infoMessage: String?
    /// The real microphones the sounds can be mixed with, and the one the user chose (nil: the system's default).
    @Published private(set) var microphones: [SoundboardRouting.Device] = []
    @Published private(set) var chosenMicrophoneUID: String?
    /// 0...1, on top of the volume of each sound.
    @Published private(set) var masterVolume: Float
    /// Off: the sounds play only on the user's own speakers, not into the call.
    @Published private(set) var sendsToCall: Bool
    /// The call hears nothing (neither the voice nor the sounds) until it is switched back.
    @Published private(set) var callMuted = false
    /// What the grid shows: one group (nil: all), and the sounds whose name has `query`.
    @Published var selectedGroup: String?
    @Published var query = ""

    let library: SoundLibrary
    let shortcuts: ShortcutManager

    private let voices = VoiceMixer()
    private let defaults: UserDefaults
    private var feed: MicFeed?
    private var feedKey: String?
    private var quietTicks = 0
    private var failedAt: Date?
    private var clips: [UUID: (rate: Double, clip: SoundClip)] = [:]
    private var monitorData: [UUID: Data] = [:]
    private var players: [AVAudioPlayer] = []

    /// How many refreshes (about a second each) the feed stays up after the call stopped reading the virtual
    /// microphone, so a call that restarts its audio does not make the feed flap.
    private static let feedLinger = 3
    /// The rate the sounds are decoded at for the user's own speakers.
    private static let monitorRate = 48_000.0
    private enum Keys {
        static let microphone = "soundboardMicrophoneUID"
        static let master = "soundboardMasterVolume"
        static let sendsToCall = "soundboardSendsToCall"
    }

    init(
        library: SoundLibrary = SoundLibrary(directory: SoundLibrary.defaultDirectory),
        shortcuts: ShortcutManager? = nil, defaults: UserDefaults = .standard
    ) {
        self.library = library
        self.shortcuts = shortcuts ?? ShortcutManager()
        self.defaults = defaults
        sounds = library.sounds
        groups = library.groups
        chosenMicrophoneUID = defaults.string(forKey: Keys.microphone)
        masterVolume = defaults.object(forKey: Keys.master) as? Float ?? 1
        sendsToCall = defaults.object(forKey: Keys.sendsToCall) as? Bool ?? true
    }

    /// The sounds the grid shows now.
    var visibleSounds: [Sound] { SoundFilter.apply(sounds, group: selectedGroup, query: query) }

    /// Chooses the microphone the sounds are mixed with; nil goes back to the system's default input.
    func chooseMicrophone(_ uid: String?) {
        chosenMicrophoneUID = uid
        if let uid {
            defaults.set(uid, forKey: Keys.microphone)
        } else {
            defaults.removeObject(forKey: Keys.microphone)
        }
    }

    func setMasterVolume(_ volume: Float) {
        masterVolume = max(0, min(1, volume))
        defaults.set(masterVolume, forKey: Keys.master)
    }

    func setSendsToCall(_ sends: Bool) {
        sendsToCall = sends
        defaults.set(sends, forKey: Keys.sendsToCall)
    }

    // MARK: - Playing

    func play(_ sound: Sound) {
        players.removeAll { !$0.isPlaying }
        let gain = sound.gain(master: masterVolume)
        do {
            let player = try AVAudioPlayer(
                data: try monitorWAV(for: sound), fileTypeHint: AVFileType.wav.rawValue)
            player.volume = gain
            player.play()
            players.append(player)
        } catch let error as AudioDecoder.DecodeError {
            errorMessage = error.localizedDescription
            return
        } catch {
            errorMessage = L.couldNotPlaySound.formatted(sound.name)
            return
        }
        guard sendsToCall, let feed else { return }
        do {
            voices.trigger(try clip(for: sound, rate: feed.sampleRate), gain: gain)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopAll() {
        voices.stopAll()
        for player in players { player.stop() }
        players.removeAll()
    }

    /// What a shortcut is called when the user is told about it: the sound's name, or the action.
    func name(of action: ShortcutAction) -> String {
        switch action {
        case .sound(let id): sounds.first { $0.id == id }?.name ?? "?"
        case .stopAll: L.actionStopAll.string
        case .callMute: L.actionCallMute.string
        case .micMute: L.actionMicMute.string
        }
    }

    /// What to tell the user about the result of giving something a shortcut, or nil when it went well.
    func problem(with result: ShortcutManager.AssignResult) -> String? {
        switch result {
        case .ok: nil
        case .invalid: L.shortcutNeedsModifier.string
        case .conflict(let other): L.shortcutInUse.formatted(name(of: other))
        case .unavailable: L.shortcutUnavailable.string
        }
    }

    /// What a global shortcut does. (The microphone one is the mixer's.)
    func perform(_ action: ShortcutAction) {
        switch action {
        case .sound(let id):
            if let sound = sounds.first(where: { $0.id == id }) { play(sound) }
        case .stopAll: stopAll()
        case .callMute: toggleCallMute()
        case .micMute: break
        }
    }

    /// Silences, or brings back, everything the call hears from SoundBar: the voice and the sounds. It only has a
    /// meaning while the sounds are going into a call.
    func toggleCallMute() {
        guard feed != nil else { return }
        setCallMuted(!callMuted)
    }

    private func setCallMuted(_ muted: Bool) {
        callMuted = muted
        voices.setCallMuted(muted)
    }

    /// A player for a sound that is being edited, to hear the section and the volume before saving. The caller keeps
    /// and stops it.
    func previewPlayer(
        url: URL, trimStart: Double, trimEnd: Double?, normalize: Bool, volume: Float
    ) throws -> AVAudioPlayer {
        let clip = try AudioDecoder.decode(
            url: url, sampleRate: Self.monitorRate, trimStart: trimStart, trimEnd: trimEnd, normalize: normalize)
        let player = try AVAudioPlayer(
            data: clip.wavData(sampleRate: Self.monitorRate), fileTypeHint: AVFileType.wav.rawValue)
        player.volume = volume * masterVolume
        return player
    }

    private func clip(for sound: Sound, rate: Double) throws -> SoundClip {
        if let cached = clips[sound.id], cached.rate == rate { return cached.clip }
        let clip = try decode(sound, rate: rate)
        clips[sound.id] = (rate, clip)
        return clip
    }

    private func monitorWAV(for sound: Sound) throws -> Data {
        if let cached = monitorData[sound.id] { return cached }
        let data = try decode(sound, rate: Self.monitorRate).wavData(sampleRate: Self.monitorRate)
        monitorData[sound.id] = data
        return data
    }

    private func decode(_ sound: Sound, rate: Double) throws -> SoundClip {
        try AudioDecoder.decode(
            url: library.audioURL(for: sound), sampleRate: rate, trimStart: sound.trimStart, trimEnd: sound.trimEnd,
            normalize: sound.normalize)
    }

    private func forget(_ id: UUID) {
        clips[id] = nil
        monitorData[id] = nil
    }

    // MARK: - The library

    @discardableResult
    func add(_ draft: SoundLibrary.Draft) throws -> Sound {
        let sound = try library.add(draft)
        reload()
        return sound
    }

    func update(_ sound: Sound, with draft: SoundLibrary.Draft) throws {
        try library.update(sound.id, with: draft)
        forget(sound.id)
        reload()
    }

    func remove(_ sound: Sound) {
        library.remove(sound.id)
        forget(sound.id)
        shortcuts.assign(nil, to: .sound(sound.id))
        reload()
    }

    /// Puts `sound` just before `target`, or at the end.
    func move(_ sound: Sound, before target: Sound?) {
        library.move(sound.id, before: target?.id)
        reload()
    }

    func shift(_ sound: Sound, by offset: Int) {
        library.shift(sound.id, by: offset)
        reload()
    }

    func exportLibrary(to url: URL) throws { try library.export(to: url) }

    @discardableResult
    func importLibrary(from url: URL) throws -> SoundLibrary.TransferResult {
        let result = try library.importLibrary(from: url)
        reload()
        return result
    }

    private func reload() {
        sounds = library.sounds
        groups = library.groups
        if let selectedGroup, !groups.contains(selectedGroup) { self.selectedGroup = nil }
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
            setState(.failed(L.noMicrophoneFound.string))
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
        setCallMuted(false)
        feed?.stop()
        feed = nil
        feedKey = nil
        voices.stopAll()
    }

    private func setState(_ new: SoundboardState) {
        if state != new { state = new }
    }
}
