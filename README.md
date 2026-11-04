# SoundBar

<img src="assets/icon-app.svg" width="96" align="right" alt="SoundBar icon">

A volume mixer for the macOS menu bar.

- **One slider per app** (and a mute button): turn Spotify down without touching the system volume. Up to 150%.
- **The microphone, in sight:** the menu bar icon turns into a microphone while any app uses it, and one click mutes it
  for everybody.
- **One slider per Chrome tab**, and the microphone of each tab, with the companion extension **SoundBar Bridge**.

The interface is in Portuguese.

## Install

Download the two files of the [latest release](../../releases/latest):

| File | What it is |
| --- | --- |
| `SoundBar-v<version>.dmg` | The app (macOS 14.2 or later, Apple silicon and Intel). Open it and drag SoundBar to Applications. |
| `SoundBar-Bridge-v<version>.zip` | The Chrome extension (Chrome 116 or later). Optional: only for per-tab control. |

**The extension:** unzip it, open `chrome://extensions`, turn on *Developer mode*, choose *Load unpacked* and pick the
unzipped folder.

**The first time:** SoundBar asks for *System Audio Recording* when you first change the volume of an app. That
permission is how it hears the apps it turns down.

**If macOS refuses to open the app** (a build that was not notarized, see [Releases](#releases)): run
`xattr -dr com.apple.quarantine /Applications/SoundBar.app` once, or use *System Settings > Privacy & Security > Open
Anyway*. A build that is not signed with a Developer ID is a different app to macOS every time, so it also asks for the
permission again after each update.

## Build it

You need the Xcode Command Line Tools (`xcode-select --install`), and for the extension Node 22+ and pnpm.

```sh
make app          # build/SoundBar.app
make run          # build it and (re)open it
make dmg          # build/SoundBar-v<version>.dmg
make extension    # ChromeExtension/dist, to load unpacked
make zip          # build/SoundBar-Bridge-v<version>.zip
make test         # the Swift tests and the extension's
make check        # what the pipeline checks: formatting, lint, types, tests, and the whole app compiling without warnings
make              # the rest of the targets
```

`./build.sh [--run]` still works. `scripts/build-app.sh` takes the version, the architectures (`ARCHS="arm64 x86_64"`)
and the signing identity (`SIGN_IDENTITY`) from the environment; each script says what it reads at the top.

### Why swiftc, and not the Swift Package Manager

The app is built by `swiftc` directly (`scripts/build-app.sh`), and its tests by `swiftc` too (`scripts/test.sh`, with
Swift Testing). The Command Line Tools of some macOS releases have a Swift Package Manager whose manifest library does
not even link, so a `Package.swift` would not work for the people who have no Xcode. The pipeline runs these same
scripts, so what is built on a laptop is what is built there. If you work in Xcode, a package can be added next to them.

## How it is made

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
`chrome-extension://…`: a web page that tries to connect is answered with an error (checked in a real browser). A
connection that says nothing for 15 seconds is dropped. The app is not sandboxed, because process taps and the process
list need it; it is signed with the hardened runtime and the one entitlement that asks for (`audio-input`).

## Releases

`.github/workflows/pipeline.yml`:

| On | What happens |
| --- | --- |
| a pull request | the extension is linted, type-checked, tested and zipped; the app is format-checked, tested, built (universal) and put in a disk image. Both come out as artifacts of the run. |
| a push to `main` | the same, then a GitHub release `v<major>.<minor>.<patch>` with the disk image, the zip and `SHA256SUMS.txt`. |

The version: the file `VERSION` holds `major.minor.patch`; only the first two numbers are chosen by hand. On `main` the
patch counts up from the releases that already exist, so a merge never needs a version bump (`scripts/release.mjs`). The
same number goes in the app (`Info.plist`) and in the extension (`manifest.json`).

**Signing and notarization** switch on by themselves when these repository secrets exist (*Settings > Secrets and
variables > Actions*), and only for a push to `main`: a pull request never gets the secrets, not even one from this
repository, and each secret goes only to the step that uses it. Without them the release still builds, signed ad hoc.
If the secrets are there but the certificate cannot be imported, the run fails instead of releasing an ad hoc build.

| Secret | What |
| --- | --- |
| `MACOS_CERTIFICATE` | the *Developer ID Application* certificate, exported as `.p12` and base64 encoded: `base64 -i certificate.p12 \| pbcopy` |
| `MACOS_CERTIFICATE_PASSWORD` | the password chosen when exporting it |
| `NOTARY_APPLE_ID` | the Apple ID that belongs to the developer account |
| `NOTARY_TEAM_ID` | the ten characters of the team |
| `NOTARY_PASSWORD` | an [app-specific password](https://support.apple.com/102654) for that Apple ID |

## Known limits

- The *System Audio Recording* permission has no public API to ask about; `AudioCapturePermission` reads it the way
  the system does, through the private TCC framework. It works today, and may need a change in a future macOS.
- A boost above 100% is limited to full scale, so a loud source can distort.
- The extension needs the app: without it the tabs are listed nowhere and nothing is changed. It keeps trying to
  connect, so opening the app later is enough.
- The logic of the realtime audio path and of the bridge is tested; the taps themselves (a real device, a real
  permission) are not, and neither is the notarization.
- The extension is installed by hand (*Load unpacked*), not from the Chrome Web Store: its content script runs on every
  site (`<all_urls>`), which the store reviews closely. Per-tab control needs that, because the volume is applied inside
  the page.

## Contributing

Issues and pull requests are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md). For a security problem, see
[SECURITY.md](SECURITY.md) and do not open a public issue.

## License

[MIT](LICENSE)
# soundbar-mac
