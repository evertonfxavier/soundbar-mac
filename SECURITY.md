# Security policy

## What to know about SoundBar's attack surface

SoundBar is not sandboxed, because Core Audio process taps and the process list need that. It:

- **listens on `127.0.0.1:38765`** for the Chrome extension. A WebSocket is accepted only when its `Origin` starts with
  `chrome-extension://`; web pages are refused, and a connection that stays silent for 15 seconds is dropped. The
  socket is never bound to a non-loopback address.
- **intercepts the audio of other apps** (System Audio Recording permission) in order to change their volume.
- **reads the TCC permission state through a private framework**, since there is no public API for it.
- ships a Chrome extension with a content script on `<all_urls>` and the `tabs` permission. It reports only the tab
  title, host and favicon of tabs that make sound or use the microphone, and only to the local app.

## Supported versions

Only the [latest release](../../releases/latest) gets fixes.

## Reporting a vulnerability

Please **do not open a public issue** for a security problem. Use GitHub's private reporting instead: *Security* tab >
*Report a vulnerability* ([direct link](../../security/advisories/new)).

Helpful in a report: the SoundBar version, the macOS and Chrome versions, what an attacker needs (a web page? another
local process? a local user?), and steps to reproduce.

This is a volunteer project: expect an answer within about a week, and a fix as soon as it can be made and tested.
Reporters are credited in the release notes unless they prefer not to be.

Things that are **in scope**: a web page or another origin driving the bridge, another local user or app abusing the
port to read tab data or change volumes, anything that makes the app or the extension leak data off the machine.

Things that are **out of scope**: other processes running as the same user (they can already do what SoundBar can), and
the ad hoc signature of unofficial builds.
