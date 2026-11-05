import SwiftUI

/// The default speaker or microphone: its name, its volume and a mute button.
struct DeviceRow: View {
    let title: String
    let device: DeviceState
    /// The devices the user can switch to, and what to do when one is picked (by its uid).
    let choices: [SoundboardRouting.Device]
    let select: (String) -> Void
    let onSymbol: String
    let offSymbol: String
    let setVolume: (Float) -> Void
    let toggleMute: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title).font(.callout.weight(.semibold))
                DevicePicker(title: title, current: device, choices: choices, select: select)
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
                    .accessibilityLabel(L.volumeOf.formatted(title))
            }
        }
    }
}

/// The name of the device, as a menu to switch to another one.
private struct DevicePicker: View {
    let title: String
    let current: DeviceState
    let choices: [SoundboardRouting.Device]
    let select: (String) -> Void

    var body: some View {
        Menu {
            ForEach(choices) { choice in
                Button {
                    select(choice.uid)
                } label: {
                    if choice.uid == current.uid {
                        Label(choice.name, systemImage: "checkmark")
                    } else {
                        Text(choice.name)
                    }
                }
            }
        } label: {
            Text("· \(current.name)").font(.caption).lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .disabled(choices.count < 2)
        .help(L.switchDevice.formatted(title.lowercased()))
        .accessibilityLabel(L.deviceOf.formatted(title, current.name))
    }
}
