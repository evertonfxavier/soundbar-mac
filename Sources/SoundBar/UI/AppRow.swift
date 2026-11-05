import SwiftUI

/// One app that plays sound or uses the microphone, with its own volume and mute.
struct AppRow: View {
    @EnvironmentObject var mixer: Mixer
    let app: AudioApp

    var body: some View {
        let s = mixer.setting(for: app.id)
        HStack(alignment: .center, spacing: 10) {
            Group {
                if let icon = app.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
                }
            }
            .frame(width: 26, height: 26)
            .opacity(app.isPlaying || app.isUsingMic ? 1 : 0.5)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(app.name).font(.callout).lineLimit(1)
                    if app.isPlaying {
                        Image(systemName: "waveform").font(.caption2).foregroundStyle(.green)
                            .help(L.playingAudio.string)
                            .accessibilityLabel(L.playingAudio.string)
                    }
                    if app.isUsingMic {
                        Image(systemName: "mic.fill").font(.caption2).foregroundStyle(.red)
                            .help(L.usingMicrophone.string)
                            .accessibilityLabel(L.usingMicrophone.string)
                    }
                    Spacer()
                    Text(s.muted ? L.mutedLabel.string : "\(Int((s.volume * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(s.isDefault ? .secondary : .primary)
                        .onTapGesture(count: 2) { mixer.reset(app.id) }
                        .help(L.doubleClickReset.string)
                }
                HStack(spacing: 8) {
                    MuteButton(
                        muted: s.muted, onSymbol: "speaker.wave.2.fill", offSymbol: "speaker.slash.fill",
                        subject: app.name
                    ) {
                        mixer.toggleMute(app.id)
                    }
                    Slider(
                        value: Binding(
                            get: { s.volume },
                            set: { mixer.setVolume($0, for: app.id) }
                        ), in: 0...AppSetting.maxVolume
                    )
                    .controlSize(.small)
                    .disabled(mixer.permission == .denied)
                    .accessibilityLabel(L.volumeOf.formatted(app.name))
                }
                if let err = mixer.errors[app.id] {
                    Text(err).font(.caption2).foregroundStyle(.red).lineLimit(2)
                }
            }
        }
    }
}
