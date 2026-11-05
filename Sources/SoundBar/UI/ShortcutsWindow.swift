import AppKit
import SwiftUI

/// The window with the shortcuts of the soundboard and of the microphone. (The shortcut of each sound is set in the
/// editor of that sound.)
@MainActor
enum ShortcutsWindow {
    private static var window: NSWindow?

    static func show(soundboard: Soundboard) {
        window?.close()
        let controller = NSHostingController(
            rootView: ShortcutsView(shortcuts: soundboard.shortcuts, soundboard: soundboard))
        let new = NSWindow(contentViewController: controller)
        new.title = L.shortcutsTitle.string
        new.styleMask = [.titled, .closable]
        new.isReleasedWhenClosed = false
        new.center()
        NSApp.activate(ignoringOtherApps: true)
        new.makeKeyAndOrderFront(nil)
        window = new
    }
}

/// What went wrong with the last shortcut, if anything.
private final class ShortcutsMessages: ObservableObject {
    @Published var message: String?
    @Published var recorderMessage: String?
}

private struct ShortcutsView: View {
    @ObservedObject var shortcuts: ShortcutManager
    let soundboard: Soundboard
    @StateObject private var model = ShortcutsMessages()

    private static let actions: [(ShortcutAction, L)] = [
        (.callMute, .actionCallMute), (.stopAll, .actionStopAll), (.micMute, .actionMicMute),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L.shortcutsHelp.string)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Self.actions, id: \.0) { action, title in
                LabeledContent(title.string) {
                    ShortcutRecorder(
                        combo: Binding(
                            get: { shortcuts.combo(for: action) },
                            set: { assign($0, to: action) }
                        ), message: $model.recorderMessage)
                }
            }

            if let text = model.message ?? model.recorderMessage {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func assign(_ combo: KeyCombo?, to action: ShortcutAction) {
        model.message = soundboard.problem(with: shortcuts.assign(combo, to: action))
    }
}
