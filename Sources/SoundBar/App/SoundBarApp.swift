import SwiftUI

@main
struct SoundBarApp: App {
    // Created with the app, not when the menu is first opened: the taps of the apps the user changed in an earlier
    // session start at launch, and the Chrome extension connects at once. The `Mixer` also destroys its taps when
    // the app quits.
    @StateObject private var mixer = Mixer()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(mixer)
        } label: {
            Image(systemName: mixer.menuBarSymbol)
                .accessibilityLabel("SoundBar")
        }
        .menuBarExtraStyle(.window)
    }
}
