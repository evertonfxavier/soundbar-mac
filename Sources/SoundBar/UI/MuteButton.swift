import SwiftUI

/// The speaker or microphone button that mutes and unmutes. `subject` says what it mutes, for VoiceOver.
struct MuteButton: View {
    let muted: Bool
    let onSymbol: String
    let offSymbol: String
    let subject: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: muted ? offSymbol : onSymbol)
                .frame(width: 18)
                .foregroundStyle(muted ? Color.red : Color.primary)
        }
        .buttonStyle(.borderless)
        .help(muted ? "Desmutar" : "Mutar")
        .accessibilityLabel("\(muted ? "Desmutar" : "Mutar") \(subject)")
    }
}
