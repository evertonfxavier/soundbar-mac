import SwiftUI

/// One browser tab (reported by the Chrome extension), with its own volume, mute and microphone switch.
struct TabRow: View {
    @EnvironmentObject var mixer: Mixer
    let tab: BrowserTab

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AsyncImage(url: tab.favIconURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "globe").resizable().scaledToFit().foregroundStyle(.secondary)
            }
            .frame(width: 22, height: 22)
            .opacity(tab.audible || tab.mic ? 1 : 0.5)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(tab.displayName).font(.callout).lineLimit(1)
                    if tab.audible {
                        Image(systemName: "waveform").font(.caption2).foregroundStyle(.green)
                            .accessibilityLabel(L.playingAudio.string)
                    }
                    if tab.mic {
                        Image(systemName: "mic.fill").font(.caption2).foregroundStyle(.red)
                            .accessibilityLabel(L.usingMicrophone.string)
                    }
                    Spacer()
                    Text(tab.muted ? L.mutedLabel.string : "\(Int((tab.volume * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .onTapGesture(count: 2) { mixer.resetTab(tab) }
                        .help(L.doubleClickRestore.string)
                }
                if !tab.host.isEmpty && tab.host != tab.displayName {
                    Text(tab.host).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 8) {
                    MuteButton(
                        muted: tab.muted, onSymbol: "speaker.wave.2.fill", offSymbol: "speaker.slash.fill",
                        subject: tab.displayName
                    ) {
                        mixer.toggleTabMute(tab)
                    }
                    Slider(
                        value: Binding(
                            get: { tab.volume },
                            set: { mixer.setTabVolume(tab, $0) }
                        ), in: 0...1
                    )
                    .controlSize(.small)
                    .accessibilityLabel(L.volumeOf.formatted(tab.displayName))
                    if tab.mic {
                        MuteButton(
                            muted: tab.micMuted, onSymbol: "mic.fill", offSymbol: "mic.slash.fill",
                            subject: L.microphoneOfThing.formatted(tab.displayName)
                        ) {
                            mixer.toggleTabMic(tab)
                        }
                    }
                }
            }
        }
    }
}
