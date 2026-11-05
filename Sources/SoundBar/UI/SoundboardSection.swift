import AppKit
import SwiftUI

/// The "SONOPLASTIA" section of the menu: a button per sound, and what it takes to hear them in a call.
struct SoundboardSection: View {
    @EnvironmentObject var soundboard: Soundboard

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    /// With more sounds than this the search box appears, and the grid scrolls.
    private static let searchThreshold = 12

    var body: some View {
        CollapsibleSection(
            .soundboard, title: L.sectionSoundboard.string, count: soundboard.sounds.count,
            trailing: { headerButtons }
        ) {
            // Without BlackHole the soundboard is off: say how to turn it on, and show the sounds dimmed.
            if !soundboard.isAvailable {
                SoundboardStatus(state: soundboard.state)
            }

            VStack(alignment: .leading, spacing: 8) {
                if !soundboard.groups.isEmpty {
                    GroupChips()
                }

                if soundboard.sounds.count > Self.searchThreshold || !soundboard.query.isEmpty {
                    TextField(L.searchSounds.string, text: $soundboard.query)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                }

                if soundboard.sounds.isEmpty {
                    Text(L.noSoundsYet.string)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 6)
                } else if soundboard.sounds.count > Self.searchThreshold {
                    ScrollView { grid }.frame(height: 200)
                } else {
                    grid
                }

                if !soundboard.sounds.isEmpty {
                    MasterVolumeRow()
                }
            }
            .disabled(!soundboard.isAvailable)
            .allowsHitTesting(soundboard.isAvailable)
            .opacity(soundboard.isAvailable ? 1 : 0.4)

            if soundboard.isAvailable {
                Toggle(
                    L.sendToCall.string,
                    isOn: Binding(
                        get: { soundboard.sendsToCall },
                        set: { soundboard.setSendsToCall($0) }
                    )
                )
                .toggleStyle(.checkbox)
                .font(.caption)
                .help(L.sendToCallHelp.string)

                SoundboardStatus(state: soundboard.state)

                if soundboard.microphones.count > 1 {
                    MicrophonePicker()
                }
            }

            if let message = soundboard.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture { soundboard.errorMessage = nil }
            }
            if let message = soundboard.infoMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture { soundboard.infoMessage = nil }
            }
        }
    }

    /// The buttons at the right of the title: stop everything, the library menu and add a sound.
    private var headerButtons: some View {
        HStack(spacing: 8) {
            Button {
                soundboard.stopAll()
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.borderless)
            .help(L.stopAllSounds.string)
            .accessibilityLabel(L.stopAllSounds.string)
            Menu {
                Button(L.shortcutsMenu.string) { ShortcutsWindow.show(soundboard: soundboard) }
                Divider()
                Button(L.exportLibrary.string) { LibraryFiles.export(soundboard) }
                Button(L.importLibrary.string) { LibraryFiles.import(soundboard) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L.libraryMenu.string)
            .accessibilityLabel(L.libraryMenu.string)
            Button {
                SoundEditorWindow.show(editing: nil, soundboard: soundboard)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help(L.addSound.string)
            .accessibilityLabel(L.addSound.string)
        }
        .disabled(!soundboard.isAvailable)
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(soundboard.visibleSounds) { sound in
                SoundButton(sound: sound)
            }
        }
    }
}

/// "All" and a chip per group: one tap shows only the sounds of that group.
private struct GroupChips: View {
    @EnvironmentObject var soundboard: Soundboard

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(L.allGroups.string, selected: soundboard.selectedGroup == nil) { soundboard.selectedGroup = nil }
                ForEach(soundboard.groups, id: \.self) { group in
                    chip(group, selected: soundboard.selectedGroup == group) { soundboard.selectedGroup = group }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(
                    selected ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The volume of all the sounds together, on top of the volume of each.
private struct MasterVolumeRow: View {
    @EnvironmentObject var soundboard: Soundboard

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.wave.2").foregroundStyle(.secondary).frame(width: 18)
            Slider(
                value: Binding(
                    get: { Double(soundboard.masterVolume) },
                    set: { soundboard.setMasterVolume(Float($0)) }
                ), in: 0...1
            )
            .controlSize(.small)
            .accessibilityLabel(L.masterVolume.string)
            Text("\(Int((soundboard.masterVolume * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .help(L.masterVolume.string)
    }
}

private struct SoundButton: View {
    @EnvironmentObject var soundboard: Soundboard
    let sound: Sound

    private var help: String {
        let combo = soundboard.shortcuts.combo(for: .sound(sound.id))
        return combo.map { "\(sound.name) (\($0.display))" } ?? sound.name
    }

    var body: some View {
        Button {
            soundboard.play(sound)
        } label: {
            VStack(spacing: 3) {
                SoundIconView(icon: sound.icon, library: soundboard.library)
                    .frame(width: 32, height: 32)
                Text(sound.name)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(sound.name)
        .draggable(sound.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let id = UUID(uuidString: raw),
                let dragged = soundboard.sounds.first(where: { $0.id == id })
            else { return false }
            soundboard.move(dragged, before: sound)
            return true
        }
        .contextMenu {
            Button(L.edit.string) { SoundEditorWindow.show(editing: sound, soundboard: soundboard) }
            Button(L.moveEarlier.string) { soundboard.shift(sound, by: -1) }
            Button(L.moveLater.string) { soundboard.shift(sound, by: 1) }
            Divider()
            Button(L.remove.string, role: .destructive) { soundboard.remove(sound) }
        }
    }
}

struct SoundIconView: View {
    let icon: SoundIcon
    let library: SoundLibrary

    var body: some View {
        switch icon {
        case .emoji(let text):
            Text(text).font(.system(size: 26))
        case .image(let fileName):
            if let image = library.image(named: fileName) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "speaker.wave.2.fill").foregroundStyle(.secondary)
            }
        }
    }
}

/// What the user has to do, or can see, to have the sounds heard in a call.
private struct SoundboardStatus: View {
    @EnvironmentObject var soundboard: Soundboard
    let state: SoundboardState

    var body: some View {
        switch state {
        case .noDriver:
            VStack(alignment: .leading, spacing: 4) {
                Label(L.statusNoDriver.string, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(L.copyCommand.string) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("brew install blackhole-2ch", forType: .string)
                    }
                    Link(L.website.string, destination: URL(string: "https://existential.audio/blackhole/")!)
                }
                .controlSize(.small)
                .font(.caption)
            }
        case .idle:
            Label(L.statusIdle.string, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .live:
            HStack(spacing: 6) {
                Circle().fill(soundboard.callMuted ? Color.red : Color.green).frame(width: 7, height: 7)
                Text(soundboard.callMuted ? L.callMutedStatus.string : L.statusLive.string)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                    soundboard.toggleCallMute()
                } label: {
                    Image(systemName: soundboard.callMuted ? "mic.slash.fill" : "mic.fill")
                        .foregroundStyle(soundboard.callMuted ? Color.red : Color.primary)
                }
                .buttonStyle(.borderless)
                .help(soundboard.callMuted ? L.unmuteCall.string : L.muteCall.string)
                .accessibilityLabel(soundboard.callMuted ? L.unmuteCall.string : L.muteCall.string)
            }
            .accessibilityElement(children: .contain)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Which real microphone the sounds are mixed with: the system's default, or one the user picks (a headset, say).
private struct MicrophonePicker: View {
    @EnvironmentObject var soundboard: Soundboard

    private var currentName: String {
        soundboard.microphones.first { $0.uid == soundboard.chosenMicrophoneUID }?.name ?? L.languageAutomatic.string
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(L.soundsMicrophone.string).font(.caption).foregroundStyle(.secondary)
            Menu {
                Button {
                    soundboard.chooseMicrophone(nil)
                } label: {
                    if soundboard.chosenMicrophoneUID == nil {
                        Label(L.automaticSystem.string, systemImage: "checkmark")
                    } else {
                        Text(L.automaticSystem.string)
                    }
                }
                Divider()
                ForEach(soundboard.microphones) { mic in
                    Button {
                        soundboard.chooseMicrophone(mic.uid)
                    } label: {
                        if mic.uid == soundboard.chosenMicrophoneUID {
                            Label(mic.name, systemImage: "checkmark")
                        } else {
                            Text(mic.name)
                        }
                    }
                }
            } label: {
                Text(currentName).font(.caption).lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
        }
        .accessibilityElement(children: .contain)
    }
}
