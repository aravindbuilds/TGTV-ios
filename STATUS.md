# TGTV-ios — Status & Handoff

_Last updated: 26 Nov 2026_

## Where things stand

| Item | Status |
|---|---|
| Repo (local) | `C:\Users\ARAVIND ES\Projects\TGTV-ios` |
| Repo (GitHub) | https://github.com/aravindbuilds/TGTV-ios — `main` |
| iOS source | ~3.6k lines of Swift/SwiftUI, generated Xcode project via `project.yml` + XcodeGen |
| Cloud IPA build | Working — GitHub Actions `macos-15`, TDLibKit 1.8.70 SPM binary, unsigned IPA artifact per run |
| Device | iPhone, iOS 18.3, UDID `00008110-001C545C0C44401E`, USB |
| Install method | Sideloadly (`C:\Users\ARAVIND ES\AppData\Local\Sideloadly\sideloadly.exe`), saved free Apple ID, 9 App IDs remaining |
| Login on device | In progress — real TDLib errors are now surfaced, so the next run tells us exactly what fails |

## What has been done

### App (1:1 port of the Android `TGTVMobile` client)
- TDLib authentication state machine: phone / SMS code / 2FA / bot token / registration.
- Phone login now matches Android: country-code picker (`+91` default, same list as
  `CountryCodes.kt`), national number typed without the country code, and the full
  `+<dial><number>` is composed before it reaches TDLib.
- Baked API credentials: the API ID/hash form is **skipped** whenever credentials are
  compiled into the app; a "Use different API credentials" link is the only way to see it.
- First-run Telegram chat selection; library scanning from selected chats.
- Home screen: rotating hero, dismissible Continue Watching, poster grid + list view,
  per-chat grouping, series folding, search, sorting.
- Details + series screens: TMDB artwork/cast/versions, resume, versions, season/episode rows.
- Player: AVPlayer with **true progressive streaming** through a localhost byte-range HTTP
  proxy backed by TDLib partial files (2 MB aligned windows, warm-ahead), speed, aspect,
  SRT/OpenSubtitles subtitles, watch-progress persistence.
- Named favourites, `#TGTVBackup` cloud backup/restore, `TGTV ▶` cross-device progress
  sync, movie-request wizard, settings.

### Diagnostics (added 26 Nov)
- `TGTV/Core/TDLibError.swift` — `tgErrorText(_:)` prints the real TDLib
  `code: message` (e.g. `400: PHONE_NUMBER_INVALID`) instead of Swift's useless
  `TDLibKit.Error error 1` description. Used for every TDLib call.
- `TGTV/Core/TGTVLog.swift` — appends timestamped lines to
  `Library/Application Support/tgtv.log` (never credentials/phone/message content).
  Pull it with:
  `python -m pymobiledevice3 apps pull com.tgtv.iphone.5A7GX6LV4J "Library/Application Support/tgtv.log" tgtv.log`
- Every auth state transition and every failure is logged; `restart()` resets the
  auto-configure flags so "Try again" really retries.

### Build / automation
- `.github/workflows/build-ipa.yml`: checkout → Xcode → xcodegen → SPM resolve →
  generate `GeneratedSecrets.swift` from secrets (whitespace/quotes stripped) →
  unsigned build → `Payload` zip → artifact; optional signed ad-hoc path.
- GitHub secrets: `TG_API_ID`, `TG_API_HASH`, `TMDB_KEY`, `OPENSUBTITLES_KEY`
  (values from the local `C:\Users\ARAVIND ES\Projects\tgtv-secrets.properties`;
  never printed or committed).
- `.gitignore` excludes the generated project, build output, `*.ipa`, logs, secrets.

### Device / sideloading
- Developer Mode enabled; developer certificate trusted.
- App bundle id after Sideloadly re-signing: `com.tgtv.iphone.5A7GX6LV4J`.
- Sideloadly quirks seen: it disables Fake2 Anisette after a crash (accept the warning and
  press Start again), and it needs the iPhone unlocked with "Trust This Computer" accepted.

## Open issue

Login did not complete on the first baked build. The UI only said
**"TDLIBKIT ERROR ERROR 1"**, which is Swift's generic description for `TDLibKit.Error`,
so the real cause was hidden. The 26 Nov build fixes the visibility (and the
phone-number format). Next: install it, try login, and read the exact
`code: message` shown on screen (or `tgtv.log`).

Likely candidates, in order:
1. `400: PHONE_NUMBER_INVALID` — number sent without a country code (now fixed by the
   dial-code picker).
2. `400: API_ID_INVALID` / `API_ID_PUBLISHED_FLOOD` — wrong or rate-limited API credentials.
3. A `setTdlibParameters` failure (directory / language / parameter validation).

## Next steps

1. Download the newest `TGTV.ipa` artifact (see commands below).
2. Uninstall the old app, then sideload the new IPA (uninstall first so no stale
   preferences can override baked credentials):
   `python -m pymobiledevice3 apps uninstall com.tgtv.iphone.5A7GX6LV4J`
3. Open TGTV → it should show "Connecting to Telegram…" then the phone screen.
4. Enter the national number with the correct country code, tap Send code.
5. If anything fails, note the exact `code: message` and/or pull `tgtv.log`.
6. After login: validate library loading, streaming playback, subtitles, backup/restore,
   and re-sign the IPA every 7 days (free Apple ID certificate).

## Useful commands

```powershell
cd "C:\Users\ARAVIND ES\Projects\TGTV-ios"

# build + fetch the newest IPA
gh workflow run build-ipa.yml --ref main
gh run list --workflow build-ipa.yml --limit 3
gh run download <run-id> -n <artifact-name> -D .

# device inspection
python -m pymobiledevice3 apps list
python -m pymobiledevice3 apps pull com.tgtv.iphone.5A7GX6LV4J "Library/Application Support/tgtv.log" tgtv.log
python -m pymobiledevice3 apps uninstall com.tgtv.iphone.5A7GX6LV4J

# sideload
Start-Process 'C:\Users\ARAVIND ES\AppData\Local\Sideloadly\sideloadly.exe' -ArgumentList '"C:\Users\ARAVIND ES\Projects\TGTV-ios\TGTV.ipa"'
```

## Notes / caveats

- The unsigned IPA cannot be installed directly; Sideloadly re-signs it with the free
  Apple ID. Certificates expire after 7 days — press Start again with the same IPA.
- A free account allows ~10 new App ID registrations per week; renewals of the same
  bundle id do not consume another.
- No real credentials live in the repository — only GitHub Actions secrets.
