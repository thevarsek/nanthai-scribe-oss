# Mac direct releases

Sparkle 2 is pinned in SwiftPM. After resolving packages, its release tools are in
`.build/artifacts/sparkle/Sparkle/bin/` (also available in the matching distribution
from https://github.com/sparkle-project/Sparkle/releases).
DMG layout uses a separate, pinned **build-only** Swift package in `dmg-layout/`
([DSStore 1.0.0](https://github.com/sindresorhus/DSStore)). `make dmg` resolves/builds it
automatically under ignored `build/dmg-layout/`; it never links into or ships with Scribe.
It writes Finder metadata and a native Carbon background alias without Finder automation,
so it works without an interactive Finder session. No Python packages or extra manual setup are needed.

Keep tools, archives and credentials outside tracked source (or under ignored `build/`).

1. Run `bin/generate_keys` on the owner's machine. Sparkle stores the private key in
   Keychain. Set `SUPublicEDKey` in `Resources/Info.plist` to the printed **public** key,
   replacing `TODO(owner)`. Never commit/export the private key into this repository.
2. Increase `CFBundleVersion` and `CFBundleShortVersionString` in `Resources/Info.plist`.
3. Create an owner-managed notarization keychain profile with
   `xcrun notarytool store-credentials <profile>` (interactive; do not put credentials in scripts).
4. Copy `Config.local.mk.example` to ignored `Config.local.mk` and set `SIGN_ID`,
   optionally `TEAM_ID` (identity discovery filter), and `NOTARY_PROFILE`. Environment
   variables or make arguments work too. `NOTARY_PROFILE=<profile> make dmg` builds Release, embeds and signs Sparkle from
   the inside out, signs the hardened app with Developer ID, creates the branded DMG,
   signs it, submits with `notarytool --wait`, and staples it. An unset `NOTARY_PROFILE`
   stops after signing, suitable for local review without a notary submission.
5. Verify:
   ```sh
   hdiutil verify build/NanthAi-Scribe-0.1.0.dmg
   codesign --verify --deep --strict 'build/NanthAi Scribe.app'
   spctl -a -t open --context context:primary-signature -v build/NanthAi-Scribe-0.1.0.dmg
   ```
   Gatekeeper rejects a locally signed but unnotarized artifact; signing alone is not approval.
6. With the finished, stapled DMG, run:
   ```sh
   SPARKLE_BIN="$PWD/.build/artifacts/sparkle/Sparkle/bin" Tools/release/appcast.sh build/NanthAi-Scribe-0.1.0.dmg
   ```
   This runs `generate_appcast --download-url-prefix https://scribe.nanthai.tech/downloads/`
   against the local archive directory and writes/updates `website/public/appcast.xml`.
   It uses Sparkle's Keychain private key to produce the EdDSA signature. It does not upload
   anything. Keep previous DMGs in `build/appcast/` to retain previous entries/deltas.
7. Review the XML enclosure URL, signature, versions and minimum macOS version. Then, with
   the owner's go-ahead, `Tools/release/publish.sh build/NanthAi-Scribe-<version>.dmg` creates
   the GitHub Release `v<version>` on the public repo (the DMG lives there, never in git or on
   Netlify) and adds `website/public/_redirects` lines so
   `https://scribe.nanthai.tech/downloads/<file>` (the appcast URL) and
   `https://scribe.nanthai.tech/download/NanthAi-Scribe.dmg` (the site's button, always the
   latest) redirect to it. Commit and push `website/public/` to publish the feed and redirects.

Update checks are manual by default. `SUEnableAutomaticChecks=false` suppresses Sparkle's
permission prompt; the General toggle writes Sparkle's persisted preference. Opting in
schedules a daily check. Profiling and automatic downloads are disabled; no analytics.

## Privacy API inventory

The Mac privacy manifest describes linked code as well as direct calls:

- User defaults (`CA92.1`): `MacSettings` and app preferences.
- File timestamps (`C617.1`): linked MLXLMCommon `ParoQuant/PreparedCheckpoint.swift`
  reads cached model `contentModificationDate`; FluidAudio reads file attributes in its
  own download cache. These are app-owned files, never cross-app metadata.
- Boot time (`35F9.1`): Mac `MeetingCaptureSession` uses `mach_absolute_time` to align
  audio.
- Disk space (`E174.1`): shared `ModelStore` checks available capacity for a model download.

Tracking is false, tracking domains and collected-data declarations are empty. The manifests
are copied as bundle resources, including the Mac bundle assembled by `make app`.
