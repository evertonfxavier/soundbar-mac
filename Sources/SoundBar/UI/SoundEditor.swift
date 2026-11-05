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

    @Published var name: String
    @Published var iconKind: IconKind
    @Published var emoji: String
    @Published var imageURL: URL?
    @Published var audioURL: URL?
    @Published var volume: Double
    @Published var errorMessage: String?

    let isNew: Bool
    /// The audio the sound has now, shown when no new file was picked.
    let currentAudioName: String?
    private let sound: Sound?
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
        currentAudioName = sound?.fileName
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

    var canSave: Bool { isNew ? audioURL != nil : true }

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

    /// Plays the chosen file (or the one the sound has) on the speakers, to check it before saving.
    func togglePreview() {
        if let preview, preview.isPlaying {
            preview.stop()
            return
        }
        let url = audioURL ?? sound.map { soundboard.library.audioURL(for: $0) }
        guard let url, let player = try? AVAudioPlayer(contentsOf: url) else {
            errorMessage = L.couldNotPlayFile.string
            return
        }
        player.volume = Float(volume)
        player.play()
        preview = player
    }

    func save() {
        preview?.stop()
        let icon: SoundLibrary.Draft.Icon
        switch iconKind {
        case .emoji: icon = .emoji(emoji)
        case .image: icon = imageURL.map { .image($0) } ?? .keep
        }
        let draft = SoundLibrary.Draft(name: name, icon: icon, audio: audioURL, volume: Float(volume))
        do {
            if let sound {
                try soundboard.update(sound, with: draft)
            } else {
                try soundboard.add(draft)
            }
            close()
        } catch {
            errorMessage = error.localizedDescription
        }
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

            LabeledContent(L.fieldVolume.string) {
                HStack {
                    Slider(value: $model.volume, in: 0...1)
                    Text("\(Int((model.volume * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 40, alignment: .trailing)
                }
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
        .frame(width: 400)
    }
}
