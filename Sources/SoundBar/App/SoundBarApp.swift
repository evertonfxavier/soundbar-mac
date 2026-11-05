import SwiftUI

@main
struct SoundBarApp: App {
    // Created with the app, not when the menu is first opened: the taps of the apps the user changed in an earlier
    // session start at launch, and the Chrome extension connects at once. The `Mixer` also destroys its taps when
    // the app quits.
    @StateObject private var mixer = Mixer()
    @StateObject private var localizer = Localizer()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(mixer)
                .environmentObject(mixer.soundboard)
                .environmentObject(mixer.updater)
                .environmentObject(localizer)
                // Every text is drawn again when the language changes.
                .id(localizer.language)
        } label: {
            Image(systemName: mixer.menuBarSymbol)
                .accessibilityLabel("SoundBar")
        }
        .menuBarExtraStyle(.window)
    }
}
