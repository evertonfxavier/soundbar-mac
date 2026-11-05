import AVFoundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The window to add a sound or to change one. It is a window of its own, not part of the menu, because the menu
/// closes as soon as a file picker takes the focus.
@MainActor
enum SoundEditorWindow {
    private static var window: NSWindow?

    static func show(editing sound: Sound?, soundboard: Soundboard) {
        window?.close()
        let model = SoundEditorModel(editing: sound, soundboard: soundboard) { window?.close() }
        let controller = NSHostingController(rootView: SoundEditorView(model: model))
        let new = NSWindow(contentViewController: controller)
        new.title = sound == nil ? L.newSound.string : L.editSound.string
        new.styleMask = [.titled, .closable]
        new.isReleasedWhenClosed = false
        new.center()
        NSApp.activate(ignoringOtherApps: true)
        new.makeKeyAndOrderFront(nil)
        window = new
    }
}

@MainActor
final class SoundEditorModel: ObservableObject {
    enum IconKind: Hashable { case emoji, image }

    static let quickEmojis = ["🔊", "😂", "👏", "🥁", "🎺", "💥", "😱", "🎉", "🚨", "🤔", "👀", "🔔"]
    /// The shortest part of a sound that can be kept, in seconds.
    static let minimumSection = 0.1

    @Published var name: String
    @Published var iconKind: IconKind
    @Published var emoji: String
    @Published var imageURL: URL?
    @Published var audioURL: URL?
    @Published var volume: Double
    @Published var group: String
    @Published var normalize: Bool
    @Published var shortcut: KeyCombo?
    @Published var shortcutMessage: String?
    @Published var errorMessage: String?
    /// The length of the audio, in seconds (0 when it cannot be read), and the part of it that is kept.
    @Published private(set) var duration: Double
    @Published var trimStart: Double {
        didSet {
            if trimStart > trimEnd - Self.minimumSection { trimEnd = min(duration, trimStart + Self.minimumSection) }
        }
    }
    @Published var trimEnd: Double {
        didSet {
            if trimEnd < trimStart + Self.minimumSection { trimStart = max(0, trimEnd - Self.minimumSection) }
        }
    }

    /// False once a new sound has been saved: saving again changes that sound instead of adding another.
    private(set) var isNew: Bool
    private(set) var sound: Sound?
    private let soundboard: Soundboard
    private let close: () -> Void
    private var preview: AVAudioPlayer?

    init(editing sound: Sound?, soundboard: Soundboard, close: @escaping () -> Void) {
        self.sound = sound
        self.soundboard = soundboard
        self.close = close
        isNew = sound == nil
        name = sound?.name ?? ""
        volume = Double(sound?.volume ?? 1)
        group = sound?.group ?? ""
        normalize = sound?.normalize ?? true
        shortcut = sound.flatMap { soundboard.shortcuts.combo(for: .sound($0.id)) }
        let length = sound.flatMap { try? AudioDecoder.duration(of: soundboard.library.audioURL(for: $0)) } ?? 0
        duration = length
        trimStart = min(sound?.trimStart ?? 0, length)
        trimEnd = min(sound?.trimEnd ?? length, length)
        switch sound?.icon {
        case .image:
            iconKind = .image
            emoji = ""
        case .emoji(let text):
            iconKind = .emoji
            emoji = text
        case nil:
            iconKind = .emoji
            emoji = Sound.defaultEmoji
        }
    }

    var existingGroups: [String] { soundboard.groups }

    var canSave: Bool { isNew ? audioURL != nil : true }

    /// Only a sound whose length is known can be cut.
    var canTrim: Bool { duration > Self.minimumSection }

    var audioLabel: String {
        audioURL?.lastPathComponent ?? (isNew ? L.noFileChosen.string : L.keepCurrentSound.string)
    }

    func chooseAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.message = L.chooseSoundPanel.formatted(String(Int(AudioDecoder.maxDuration)))
        guard panel.runModal() == .OK, let url = panel.url else { return }
        audioURL = url
        let length = (try? AudioDecoder.duration(of: url)) ?? 0
        duration = length
        trimStart = 0
        trimEnd = length
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            name = url.deletingPathExtension().lastPathComponent
        }
    }

    func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        imageURL = url
        iconKind = .image
    }

    /// `nil` when the part kept runs to the end of the audio.
    private var effectiveTrimEnd: Double? { canTrim && trimEnd < duration - 0.005 ? trimEnd : nil }

    /// Plays the part that is kept (with the volume and the levelling chosen) on the speakers, before saving.
    func togglePreview() {
        if let preview, preview.isPlaying {
            preview.stop()
            return
        }
        guard let url = audioURL ?? sound.map({ soundboard.library.audioURL(for: $0) }) else {
            errorMessage = L.couldNotPlayFile.string
            return
        }
        do {
            let player = try soundboard.previewPlayer(
                url: url, trimStart: canTrim ? trimStart : 0, trimEnd: effectiveTrimEnd, normalize: normalize,
                volume: Float(volume))
            player.play()
            preview = player
            errorMessage = nil
        } catch let error as AudioDecoder.DecodeError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = L.couldNotPlayFile.string
        }
    }

    func save() {
        preview?.stop()
        errorMessage = nil
        if let combo = shortcut,
            let other = soundboard.shortcuts.conflict(for: combo, excluding: sound.map { .sound($0.id) })
        {
            errorMessage = L.shortcutInUse.formatted(soundboard.name(of: other))
            return
        }

        let icon: SoundLibrary.Draft.Icon
        switch iconKind {
        case .emoji: icon = .emoji(emoji)
        case .image: icon = imageURL.map { .image($0) } ?? .keep
        }
        let draft = SoundLibrary.Draft(
            name: name, icon: icon, audio: audioURL, volume: Float(volume), group: group,
            trimStart: canTrim ? trimStart : 0, trimEnd: effectiveTrimEnd, normalize: normalize)

        let saved: Sound
        do {
            if let sound {
                try soundboard.update(sound, with: draft)
                saved = soundboard.sounds.first { $0.id == sound.id } ?? sound
            } else {
                saved = try soundboard.add(draft)
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        // The sound is saved from here on: saving again must change it, not add another.
        sound = saved
        isNew = false
        audioURL = nil

        let result = soundboard.shortcuts.assign(shortcut, to: .sound(saved.id))
        if let problem = soundboard.problem(with: result) {
            errorMessage = problem
            return
        }
        close()
    }

    func cancel() {
        preview?.stop()
        close()
    }
}

struct SoundEditorView: View {
    @ObservedObject var model: SoundEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledContent(L.fieldName.string) {
                TextField(L.namePlaceholder.string, text: $model.name)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledContent(L.fieldSound.string) {
                HStack {
                    Text(model.audioLabel)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(L.choose.string) { model.chooseAudio() }
                }
            }

            if model.canTrim {
                LabeledContent(L.fieldTrim.string) {
                    VStack(spacing: 4) {
                        sectionRow(L.trimStart.string, value: $model.trimStart)
                        sectionRow(L.trimEnd.string, value: $model.trimEnd)
                    }
                }
            }

            LabeledContent(L.fieldIcon.string) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker(L.fieldIcon.string, selection: $model.iconKind) {
                        Text(L.emojiOption.string).tag(SoundEditorModel.IconKind.emoji)
                        Text(L.imageOption.string).tag(SoundEditorModel.IconKind.image)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if model.iconKind == .emoji {
                        TextField(L.emojiOption.string, text: $model.emoji)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(30)), count: 6), alignment: .leading) {
                            ForEach(SoundEditorModel.quickEmojis, id: \.self) { item in
                                Button(item) { model.emoji = item }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 20))
                            }
                        }
                    } else {
                        HStack {
                            if let url = model.imageURL, let image = NSImage(contentsOf: url) {
                                Image(nsImage: image).resizable().scaledToFill()
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            Button(model.imageURL == nil ? L.chooseImage.string : L.change.string) {
                                model.chooseImage()
                            }
                        }
                    }
                }
            }

            LabeledContent(L.fieldGroup.string) {
                HStack {
                    TextField(L.groupPlaceholder.string, text: $model.group)
                        .textFieldStyle(.roundedBorder)
                    if !model.existingGroups.isEmpty {
                        Menu {
                            ForEach(model.existingGroups, id: \.self) { group in
                                Button(group) { model.group = group }
                            }
                        } label: {
                            Image(systemName: "chevron.down.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }
                }
            }

            LabeledContent(L.fieldVolume.string) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Slider(value: $model.volume, in: 0...1)
                        Text("\(Int((model.volume * 100).rounded()))%")
                            .font(.caption.monospacedDigit())
                            .frame(width: 40, alignment: .trailing)
                    }
                    Toggle(L.normalizeVolume.string, isOn: $model.normalize)
                        .toggleStyle(.checkbox)
                        .help(L.normalizeHelp.string)
                }
            }

            LabeledContent(L.fieldShortcut.string) {
                ShortcutRecorder(combo: $model.shortcut, message: $model.shortcutMessage)
            }
            if let message = model.shortcutMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message = model.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(L.listen.string) { model.togglePreview() }
                    .disabled(model.audioURL == nil && model.isNew)
                Spacer()
                Button(L.cancel.string) { model.cancel() }
                    .keyboardShortcut(.cancelAction)
                Button(L.save.string) { model.save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSave)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func sectionRow(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.caption).frame(width: 38, alignment: .leading)
            Slider(value: value, in: 0...max(model.duration, SoundEditorModel.minimumSection))
            Text(L.secondsValue.formatted(String(format: "%.2f", value.wrappedValue)))
                .font(.caption.monospacedDigit())
                .frame(width: 52, alignment: .trailing)
        }
    }
}
