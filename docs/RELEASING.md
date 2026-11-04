# Releasing

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
