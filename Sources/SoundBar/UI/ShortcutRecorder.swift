import AppKit
import SwiftUI

/// A field that records a shortcut: click it, press the keys. Escape gives up, Delete clears it.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    /// What is wrong with the combination just pressed (it has no Control, Option or Command), or nil.
    @Binding var message: String?
    @StateObject private var state = RecorderState()

    var body: some View {
        HStack(spacing: 6) {
            Button {
                message = nil
                state.recording.toggle()
            } label: {
                Text(label)
                    .frame(minWidth: 110)
                    .foregroundStyle(state.recording ? Color.accentColor : Color.primary)
            }
            .background(KeyCatcher(active: $state.recording, onKey: handle))
            .accessibilityLabel(L.fieldShortcut.string)
            .accessibilityValue(combo?.display ?? L.noShortcut.string)
            if combo != nil {
                Button(L.clearShortcut.string) {
                    combo = nil
                    message = nil
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }

    private var label: String {
        if state.recording { return L.pressShortcut.string }
        return combo?.display ?? L.recordShortcut.string
    }

    private func handle(_ event: NSEvent) {
        let modifiers = KeyCombo.carbonModifiers(event.modifierFlags)
        if event.keyCode == 53 && modifiers == 0 {  // Escape
            state.recording = false
            return
        }
        if (event.keyCode == 51 || event.keyCode == 117) && modifiers == 0 {  // Delete
            combo = nil
            message = nil
            state.recording = false
            return
        }
        let pressed = KeyCombo(event: event)
        if pressed.isValid {
            combo = pressed
            message = nil
            state.recording = false
        } else {
            message = L.shortcutNeedsModifier.string
        }
    }
}

/// Whether the field is waiting for the keys. (An object and not `@State`: the Command Line Tools have no plugin for
/// the `@State` macro of the new SDK, so the project does not use it.)
private final class RecorderState: ObservableObject {
    @Published var recording = false
}

/// An invisible view that takes the keyboard while `active`, to read the keys of a shortcut being recorded
/// (even the ones with Command, which a plain view would not get).
private struct KeyCatcher: NSViewRepresentable {
    @Binding var active: Bool
    let onKey: (NSEvent) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onKey = onKey
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onKey = onKey
        view.active = active
        if active {
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        } else if view.window?.firstResponder === view {
            DispatchQueue.main.async { view.window?.makeFirstResponder(nil) }
        }
    }

    final class CatcherView: NSView {
        var onKey: ((NSEvent) -> Void)?
        var active = false

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            guard active else { return super.keyDown(with: event) }
            onKey?(event)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard active else { return super.performKeyEquivalent(with: event) }
            onKey?(event)
            return true
        }
    }
}
