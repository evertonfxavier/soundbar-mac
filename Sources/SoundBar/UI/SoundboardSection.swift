import AppKit
import SwiftUI

/// The "SONOPLASTIA" section of the menu: a button per sound, and what it takes to hear them in a call.
struct SoundboardSection: View {
    @EnvironmentObject var soundboard: Soundboard

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle("SONOPLASTIA")
                Spacer()
                Button {
                    soundboard.stopAll()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.borderless)
                .help("Parar todos os sons")
                .accessibilityLabel("Parar todos os sons")
                Button {
                    SoundEditorWindow.show(editing: nil, soundboard: soundboard)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Adicionar um som")
                .accessibilityLabel("Adicionar um som")
            }

            if soundboard.sounds.isEmpty {
                Text("Nenhum som ainda. Toque em + para adicionar o primeiro.")
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
            Button("Editar…") { SoundEditorWindow.show(editing: sound, soundboard: soundboard) }
            Button("Remover", role: .destructive) { soundboard.remove(sound) }
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
                    "Para os outros ouvirem os sons na chamada, instale o BlackHole (um microfone virtual gratuito).",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Copiar comando") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("brew install blackhole-2ch", forType: .string)
                    }
                    Link("Site", destination: URL(string: "https://existential.audio/blackhole/")!)
                }
                .controlSize(.small)
                .font(.caption)
            }
        case .idle:
            Label(
                "Na chamada, escolha “BlackHole 2ch” como microfone para os outros ouvirem os sons.",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        case .live:
            HStack(spacing: 6) {
                Circle().fill(Color.green).frame(width: 7, height: 7)
                Text("Os sons vão para a chamada.")
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
