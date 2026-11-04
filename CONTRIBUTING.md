# Contributing to SoundBar

Thanks for helping. Bug reports, ideas and pull requests are all welcome.

## Before you start

- For a bug, open an issue with the template; for a larger change, open an issue first so we can agree on the shape
  before you write it.
- For a security problem, **do not open an issue**: see [SECURITY.md](SECURITY.md).

## What you need

- macOS 14.2 or later with the Xcode **Command Line Tools** (full Xcode is not needed: the app is built with `swiftc`,
  see the README, "Why swiftc").
- Node.js and `pnpm` for the Chrome extension.

## The workflow

`make` lists every target. The ones you will use:

```bash
make run        # build the app and (re)open it
make extension  # build ChromeExtension/dist, to load in chrome://extensions
make test       # the Swift tests and the extension tests
make check      # everything the pipeline checks: lint, tests and a warnings-as-errors build
make format     # format the Swift sources and the extension
```

A pull request should pass `make check`. The pipeline runs the same on every pull request.

## Layout

| Where | What |
| --- | --- |
| `Sources/SoundBar/Core` | audio taps, Core Audio, the bridge server, the domain. No SwiftUI here, so it is testable. |
| `Sources/SoundBar/UI` | the menu bar views |
| `Tests/` | Swift Testing suites |
| `ChromeExtension/src` | `domain` (rules), `infra` (Chrome, WebSocket, page), `main` (wiring) |
| `contract/` | the bridge protocol and its fixtures: **both sides are tested against it** |

## Rules of thumb

- **Changing the protocol** (messages between app and extension): edit `contract/protocol.json` and the fixtures first;
  the Swift and TypeScript contract tests then show what to change on each side.
- **Tests come with the change.** The realtime audio path and the bridge are tested; keep it that way. Taps against a
  real device are the one thing tests cannot cover, so say in the pull request how you tried it by hand.
- **No new dependency** without a reason in the pull request. The app has none, and the extension has few.
- **Keep the pull request small and about one thing.** Commit messages in the imperative ("Fix the mic mute on clones").
- The interface is in Portuguese; code, comments and docs are in English.

## Releases

Merging into `main` publishes a release; the patch number is automatic. Only a change to the major or minor number in
`VERSION` is a decision for the maintainer.

## License

By contributing you agree that your contribution is licensed under the [MIT License](LICENSE).
