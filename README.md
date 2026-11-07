# Cirrus for iOS

A native iOS client for [Cirrus Mail](https://github.com/jackh54/cirrus-mail), the self-hosted email suite on Cloudflare Workers. It talks to the server over JMAP (RFC 8620 and 8621) and signs in with an app password.

![Sign-in screen](docs/screenshots/signin.png)

## Features (v0.1)
- Sign in with server URL, email and app password; discovery via `/.well-known/jmap`. Credentials are kept in the Keychain only.
- Several logins and one account per mailbox, with an account switcher.
- Folders (with roles and unread counts) and labels; threaded, paginated list with pull to refresh, swipe actions and unread dots.
- Reader: HTML in a WKWebView with JavaScript off and remote images blocked until "Load images"; plain text otherwise; links open in Safari; attachments preview in QuickLook.
- Compose: new, reply, reply all and forward as plain text, with an identity picker. Sent via Email/set and EmailSubmission/set.
- Sync with Mailbox/changes and Email/changes, a JSON cache for instant launch and offline reading, EventSource while in the foreground, best-effort background refresh.
- Search with Email/query text filters. Dynamic Type, VoiceOver labels, dark mode.

## Layout
- `Packages/JMAPKit`: the protocol client (no UI), with unit tests.
- `CirrusApp`: the SwiftUI app. `project.yml` is the XcodeGen spec; `CirrusApp.xcodeproj` is committed.

## Build
Requires Xcode 26 or later (iOS 26 SDK).

```bash
xcodebuild -scheme CirrusApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild test -scheme CirrusApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
cd Packages/JMAPKit && swift test
```

To change targets or settings, edit `project.yml` and run `xcodegen generate`. Signing is automatic with no team set: pick your team in Xcode to run on a device.

## Beta

Join the public beta on TestFlight: https://testflight.apple.com/join/u5zScSGa (iOS 26 or later). Sign in with your Cirrus server address, your email and an app password from **Settings → Security** in the Cirrus web app.

## Releasing

Xcode Cloud builds every change; versions come from git tags.

| Trigger | Xcode Cloud workflow | Goes to |
|---|---|---|
| Push to `main` | **Internal** | TestFlight, internal testers |
| Push a `vX.Y.Z` tag | **Release** | TestFlight, external group (the public beta link) |

Cut a release from an up-to-date, clean `main`:

```bash
scripts/release.sh 0.2.0
```

It sets `MARKETING_VERSION` in `project.yml` and the Xcode project, commits `chore(release): 0.2.0`, tags `v0.2.0`, pushes both and creates a GitHub release with notes generated from the commits since the last tag. Xcode Cloud then archives the tag and sends it to the external group; Apple reviews each new external version before testers get it.

Build numbers come from Xcode Cloud (`CI_BUILD_NUMBER`), so never set them by hand. `ci_scripts/ci_pre_xcodebuild.sh` stops a tag build whose version doesn't match `project.yml`. Versions follow semver: bump the patch for fixes, the minor for features. Commit messages follow Conventional Commits.

## Server
The server needs the JMAP routes (`/jmap/*`). Create an app password in the web app under Settings → Security.

## License
MIT, see `LICENSE`.
