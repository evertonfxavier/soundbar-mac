import SwiftUI

/// The default speaker or microphone: its name, its volume and a mute button.
struct DeviceRow: View {
    let title: String
    let device: DeviceState
    let onSymbol: String
    let offSymbol: String
    let setVolume: (Float) -> Void
    let toggleMute: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title).font(.callout.weight(.semibold))
                Text("· \(device.name)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if device.hasVolume {
                    Text("\(Int((device.volume * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                MuteButton(
                    muted: device.muted, onSymbol: onSymbol, offSymbol: offSymbol, subject: title,
                    action: toggleMute)
                Slider(value: Binding(get: { device.volume }, set: setVolume), in: 0...1)
                    .controlSize(.small)
                    .disabled(!device.hasVolume)
                    .accessibilityLabel("Volume de \(title)")
            }
        }
    }
}
