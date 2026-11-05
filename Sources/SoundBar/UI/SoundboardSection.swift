import AppKit
import SwiftUI

/// The "SONOPLASTIA" section of the menu: a button per sound, and what it takes to hear them in a call.
struct SoundboardSection: View {
    @EnvironmentObject var soundboard: Soundboard

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(L.sectionSoundboard.string)
                Spacer()
                Button {
                    soundboard.stopAll()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.borderless)
                .help(L.stopAllSounds.string)
                .accessibilityLabel(L.stopAllSounds.string)
                Button {
                    SoundEditorWindow.show(editing: nil, soundboard: soundboard)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help(L.addSound.string)
                .accessibilityLabel(L.addSound.string)
            }

            if soundboard.sounds.isEmpty {
                Text(L.noSoundsYet.string)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else if soundboard.sounds.count > 12 {
                ScrollView { grid }.frame(height: 200)
            } else {
                grid
            }

            SoundboardStatus(state: soundboard.state)

            if soundboard.state != .noDriver, soundboard.microphones.count > 1 {
                MicrophonePicker()
            }

            if let message = soundboard.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture { soundboard.errorMessage = nil }
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(soundboard.sounds) { sound in
                SoundButton(sound: sound)
            }
        }
    }
}

private struct SoundButton: View {
    @EnvironmentObject var soundboard: Soundboard
    let sound: Sound

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
        .help(sound.name)
        .accessibilityLabel(sound.name)
        .contextMenu {
            Button(L.edit.string) { SoundEditorWindow.show(editing: sound, soundboard: soundboard) }
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
    let state: SoundboardState

    var body: some View {
        switch state {
        case .noDriver:
            VStack(alignment: .leading, spacing: 4) {
                Label(
                    L.statusNoDriver.string,
                    systemImage: "info.circle"
                )
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
            Label(
                L.statusIdle.string,
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        case .live:
            HStack(spacing: 6) {
                Circle().fill(Color.green).frame(width: 7, height: 7)
                Text(L.statusLive.string)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
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
