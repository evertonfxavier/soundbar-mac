# Architecture

```text
Sources/SoundBar/
  App/            the @main App: a MenuBarExtra
  UI/             SwiftUI views (they only know the Mixer)
  Core/           everything that is not a view: it is also what the tests compile, so it cannot reach the UI
    Domain/       the rules that need no hardware: AppSetting, AppListing, MicUsage, BrowserTab (tested)
    Audio/        Core Audio: process taps (AppTap), devices, the owner of a process, the TCC permission
    Browser/      the local WebSocket the extension talks to (BrowserBridge) and its messages (BridgeProtocol)
    Mixer.swift   the state of the menu: watches apps and devices, keeps the settings, runs one tap per app
Tests/            Swift Testing: rules, the realtime gain kernel, the bridge against a real WebSocket client
ChromeExtension/  the extension, in TypeScript (below)
contract/         what the app and the extension agree on, read by the tests of both (below)
scripts/          build, test, disk image, notarization, icons, release numbering
assets/           the icons, as SVG
```

**How an app's volume works.** For an app with a volume or a mute set, SoundBar creates a Core Audio *process tap* that
mutes the app's own output and reads its audio, and plays it again, times a gain, on the output device the app was using
(`AppTap`). Apps left at 100% get no tap and are not touched.

**The Chrome extension** cannot change a tab's volume from outside, so it does it from inside: a script in the page's
own world scales the volume of every `<audio>` and `<video>` (the site still reads and writes its own volume) and
follows the microphone tracks from `getUserMedia`. A service worker keeps a WebSocket to the app on `127.0.0.1:38765`,
tells it which tabs make sound or use the microphone, and applies what it sends back.

```text
app (Swift)  <— WebSocket —>  service worker  <— chrome.runtime —>  relay  <— postMessage —>  inject
                                                                    (isolated world)         (page world)
```

```text
ChromeExtension/src/
  domain/    protocol, the rules that pick the tabs to show, and the service that runs the worker (no browser APIs)
  infra/     adapters: chrome.tabs, chrome.storage.session, the WebSocket, the media and the microphone of a page
  main/      the three entry points (service worker, relay, inject) and the code that wires them
```

ESLint enforces that a layer imports only from the ones inside it. Built with esbuild (`scripts/build.mjs`): each entry
point becomes one file with no imports, as a content script must be, into `dist/`.

**The contract.** `contract/protocol.json` (address, port, the `Origin` of an extension) and `contract/fixtures/` (one
example of every message) are read by `ChromeExtension/tests/contract` and by `Tests/Contract`. Change one side without
the other and one of the two suites fails.

**Security.** The app listens on the loopback only, and accepts a WebSocket only if its `Origin` is
`chrome-extension://…`: a web page that tries to connect is answered with an error (covered by the bridge tests, which use a real WebSocket client). A
connection that says nothing for 15 seconds is dropped. The app is not sandboxed, because process taps and the process
list need it; it is signed with the hardened runtime and the one entitlement that asks for (`audio-input`).
