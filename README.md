# TGTV-ios

Native iOS client for TGTV — a SwiftUI port of the Android app in
[`TGTVMobile`](https://github.com/aravindbuilds/TGTVMobile). The app uses the
same Telegram TDLib backend, TMDB metadata, OpenSubtitles lookups, and the exact
`#TGTVBackup` / `TGTV ▶` wire formats so library state and watch progress can be
shared with the phone and TV apps.

## Building an `.ipa` from Windows / VS Code

You do **not** need a Mac. A GitHub Actions macOS runner builds the app in the
cloud and attaches a real `.ipa` to every `v*` tag.

1. Push a commit to `main`, then create a tag:

   ```bash
   git tag v1.0
   git push origin v1.0
   ```

2. Open **Actions → Build IPA** and wait for the `Build TGTV.ipa on macOS` job.
3. Download `TGTV-ipa-<sha>` from the workflow run, or from the GitHub Release
   created for the tag.

You can also run the workflow manually with **Run workflow** on the Actions tab.

### Installing the IPA

| Build | How to install |
|---|---|
| **Unsigned** (default, no secrets) | Re-sign and sideload with AltStore, Sideloadly, or a similar tool. An unsigned `.ipa` cannot be installed directly on a non-jailbroken iPhone. |
| **Signed ad-hoc** (secrets configured) | Install via Apple Configurator / Xcode Devices, or distribute through TestFlight after changing `method` to `app-store`. |

An Apple Developer Program membership plus a distribution certificate and
provisioning profile are required for a signed build.

## Repository secrets

Set these under **Settings → Secrets and variables → Actions** if you want the
Telegram/TMDB/OpenSubtitles keys baked into the build and/or a signed IPA:

| Secret | Purpose |
|---|---|
| `TG_API_ID` | Telegram API id from my.telegram.org |
| `TG_API_HASH` | Telegram API hash |
| `TMDB_KEY` | TMDB v3 API key |
| `OPENSUBTITLES_KEY` | OpenSubtitles.com API key |
| `BUILD_CERTIFICATE_BASE64` | Base64 of the `.p12` distribution certificate (enables signing) |
| `P12_PASSWORD` | Password for the `.p12` |
| `BUILD_PROVISION_PROFILE_BASE64` | Base64 of the ad-hoc `.mobileprovision` |
| `PROVISIONING_PROFILE_NAME` | Provisioning profile name (also used in ExportOptions) |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `KEYCHAIN_PASSWORD` | Optional temporary keychain password |

Variables: `BUNDLE_ID` defaults to `com.tgtv.iphone`.

Keys can also be entered at runtime in **Settings**, so unsigned builds work
without any secrets.

## Local development

The project is generated with [xcodegen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
xcodegen generate
open TGTV.xcodeproj
```

Simulator builds work locally with Xcode; device/IPA builds need signing.

## What is ported

- TDLib login state machine (phone / SMS / 2FA / bot token / registration)
- First-run Telegram chat selection and library scanning
- Netflix-style Home: rotating hero, dismissible Continue Watching, poster grid
  and list views, per-chat grouping, series folding, search and sorting
- Details and series screens with TMDB artwork, cast, versions and resume
- Video player with double-tap seek, speed, aspect ratio, SRT subtitles and
  OpenSubtitles search, watch-progress persistence and cross-device sync
- Named favourite lists, cloud backup/restore through Saved Messages
- Movie request wizard (bot picker, query, gate detection, save to Saved Messages)
- Settings for keys, sync, cache, sort/layout and session management

## Known differences from the Android app

- Playback downloads the Telegram file locally before AVPlayer starts. The
  Android app uses a custom byte-range data source over TDLib's partial file;
  AVPlayer needs a local file or a local HTTP proxy, so a full download is used
  here for reliability.
- OTA APK updates and Android launcher-icon switching do not apply on iOS.
  Releases are distributed as IPAs via GitHub Actions instead.
- The movie request wizard covers search, gate replies and saving arriving
  files; some of the Android bot-specific inline-button edge cases are not yet
  ported.

## License

See the sibling TGTV project for licensing. This repository contains no keys.
