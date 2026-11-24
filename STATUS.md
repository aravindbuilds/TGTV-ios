# TGTV-ios — Status & Handoff

_Last updated: 25 Nov 2026_

## Where things stand

| Item | Status |
|---|---|
| Repo (local) | `C:\Users\ARAVIND ES\Projects\TGTV-ios` |
| Repo (GitHub) | https://github.com/aravindbuilds/TGTV-ios — `main`, pushed |
| iOS source | ~3.5k lines of Swift/SwiftUI, 21 Swift files, generated Xcode project via `project.yml` + XcodeGen |
| Cloud IPA build | Working — GitHub Actions `macos-15`, TDLibKit 1.8.70 SPM binary, unsigned IPA artifact on every run/tag |
| Latest successful build | Run `45486075449`, commit `4de42e3`, artifact `TGTV-ipa-4de42e37f91850752cb44fc896be06ab25280dba` |
| Local IPA | `C:\Users\ARAVIND ES\Projects\TGTV-ios\TGTV.ipa` (26.2 MB) — built with baked credentials |
| Device | iPhone, iOS 18.3, UDID `00008110-001C545C0C44401E`, connected by USB |
| Install method | Sideloadly 0.60.0 (`C:\Users\ARAVIND ES\AppData\Local\Sideloadly\sideloadly.exe`), Apple ID saved in app, 9 free App IDs remaining |
| Login on device | **Blocked** — see "Open issue" below |

## What has been done

### App (1:1 port of the Android `TGTVMobile` client)
- TDLib authentication state machine: phone / SMS code / 2FA / bot token / registration.
- First-run Telegram chat selection; library scanning from selected chats.
- Home screen: rotating hero, dismissible Continue Watching, poster grid + list view, per-chat grouping, series folding, search, sorting.
- Details + series screens: TMDB artwork/cast/versions, resume, versions, season/episode rows.
- Player: AVPlayer with **true progressive streaming** through a localhost byte-range HTTP proxy backed by TDLib partial files (2 MB aligned windows, warm-ahead), speed, aspect, SRT/OpenSubtitles subtitles, watch-progress persistence.
- Named favourites, `#TGTVBackup` cloud backup/restore, `TGTV ▶` cross-device progress sync, movie-request wizard, settings.
- Startup diagnostics + a 12-second "TDLib did not initialize" timeout and Retry action (added for debugging).

### Build / automation
- `.github/workflows/build-ipa.yml`: checkout → Xcode → xcodegen → SPM resolve → generate `GeneratedSecrets.swift` from secrets → unsigned build → zip `Payload` into `.ipa` → artifact; optional signed ad-hoc path if certificate secrets are supplied.
- GitHub secrets configured (values come from the local `C:\Users\ARAVIND ES\Projects\tgtv-secrets.properties`; **never printed or committed**):
  `TG_API_ID`, `TG_API_HASH`, `TMDB_KEY`, `OPENSUBTITLES_KEY`.
- Baked secrets were verified as non-empty/non-zero in the CI "Generate secrets source" step.
- `.gitignore` excludes generated project, build output, `*.ipa`, logs, and secret files.

### Device / sideloading
- Developer Mode enabled on the phone; developer certificate trusted under Settings → General → VPN & Device Management.
- App was uninstalled and reinstalled fresh via Sideloadly to clear old preferences that could override baked keys.
- Sideloadly needed the "Trust this computer" prompt accepted once; after that, install completed (`Done. 100%`).
- Sideloadly rewrites the bundle id to `com.tgtv.iphone.5A7GX6LV4J` — this is normal.

## Open issue (where to resume)

After the clean reinstall, TGTV starts but login does not complete:

- The app shows an error rendered as **"TDLIBKIT ERROR ERROR 1"** — this is Swift's generic `localizedDescription` for `TDLibKit.Error`, so the real TDLib **code + message are being hidden**.
- The user reports still being asked for API ID/hash even though credentials are baked. Either the form appears before auto-configure or `setTdlibParameters` fails and the form stays visible.
- `TDLibService.configure()` currently does `try await client.setTdlibParameters(...)`, and `LoginView` surfaces only `error.localizedDescription`.

### Next steps (recommended order)

1. **Surface the real error.** Add a helper that casts to `TDLibKit.Error` and displays `code: message` (e.g. `if let e = error as? TDLibKit.Error { "\(e.code): \(e.message)" }`). Use it in `TDLibService.configure()` catch and in `LoginView`. The code/message will identify whether this is a parameter-validation error (hash/id/directory/language) or a client-state error.
2. **Confirm baked keys are actually used.** On a fresh install `Store.apiId`/`apiHash` should fall back to `GeneratedSecrets` (UserDefaults are empty). Add a temporary diagnostic line (e.g. log only whether the baked id is non-zero and hash length, never the value) if needed.
3. **Fix `configure()`** based on the real error. Likely candidates: language code/device model being nil/empty, or `setTdlibParameters` being sent at the wrong auth state.
4. **Rebuild and reinstall:** push the fix, wait for Actions, download the artifact to `TGTV.ipa`, then relaunch Sideloadly with the IPA path and click Start (UI automation can do this). If Sideloadly reports `Fake2 Anisette disabled after a crash`, accept the warning/restart it; if the device serial is masked, accept the "Trust this computer" prompt on the phone.
5. **Verify login:** phone number → SMS code → 2FA (if enabled) → chat selection → Home.
6. After login works, validate library loading, player streaming, backup/restore, and re-signing after the 7-day free-certificate expiry.

## Useful commands

```bash
# local repo
cd "C:\Users\ARAVIND ES\Projects\TGTV-ios"

# trigger a cloud IPA build
gh workflow run build-ipa.yml --ref main
gh run list --workflow build-ipa.yml --limit 5

# download newest artifact (replace run id + artifact name)
gh run download <run-id> -n <artifact-name> -D .

# device inspection (pymobiledevice3 installed)
python -m pymobiledevice3 apps list
python -m pymobiledevice3 crash ls
python -m pymobiledevice3 syslog live -pn TGTV
python -m pymobiledevice3 apps uninstall com.tgtv.iphone.5A7GX6LV4J

# sideload (automatable via UI Automation)
Start-Process 'C:\Users\ARAVIND ES\AppData\Local\Sideloadly\sideloadly.exe' -ArgumentList '"C:\Users\ARAVIND ES\Projects\TGTV-ios\TGTV.ipa"'
```

## Notes / caveats

- Unsigned IPA cannot be installed directly; Sideloadly re-signs with the saved free Apple ID. Free certificates expire after 7 days — press Start again with the same IPA to renew.
- Free account allows ~10 new App ID registrations per week; 9 were remaining at last check. Renewals of the same bundle id do not consume another.
- The app currently shows a generic Swift error message; fixing that is step 1 above.
- No real credentials are stored in this repository — only GitHub Actions secrets.
