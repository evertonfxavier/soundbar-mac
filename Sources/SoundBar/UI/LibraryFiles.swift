import AppKit
import UniformTypeIdentifiers

/// The file panels to export and import the library of sounds. They are windows of their own, so the menu closes
/// while one is open.
@MainActor
enum LibraryFiles {
    static func export(_ soundboard: Soundboard) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "SoundBar Sounds.zip"
        panel.prompt = L.exportFilePrompt.string
        guard panel.runModal() == .OK, let url = panel.url else { return }
        soundboard.errorMessage = nil
        do {
            try soundboard.exportLibrary(to: url)
            soundboard.infoMessage = nil
        } catch {
            soundboard.errorMessage = error.localizedDescription
        }
    }

    static func `import`(_ soundboard: Soundboard) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.prompt = L.importFilePrompt.string
        guard panel.runModal() == .OK, let url = panel.url else { return }
        soundboard.errorMessage = nil
        do {
            let result = try soundboard.importLibrary(from: url)
            soundboard.infoMessage = L.importResult.formatted(
                String(result.added), String(result.skipped), String(result.failed))
        } catch {
            soundboard.errorMessage = error.localizedDescription
        }
    }
}
