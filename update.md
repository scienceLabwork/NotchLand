# Updating NotchLand (Over-the-Air with Sparkle)

NotchLand ships over-the-air (OTA) updates using [Sparkle 2](https://sparkle-project.org).
This document is the **maintainer's release guide**: how auto-updates work, what's already
wired up, and the exact steps to publish a new version.

> **TL;DR** — Bump the version → build a **Developer ID–signed** app → zip it →
> `generate_appcast` → attach the `.zip` **and** `appcast.xml` to a GitHub Release.
> Existing users get prompted on their next check.

---

## How it works

Sparkle is pull-based. Three pieces talk to each other:

```
   NotchLand (running)                 GitHub Releases               You (maintainer)
 ┌────────────────────┐            ┌────────────────────┐        ┌──────────────────┐
 │ SUFeedURL +        │  ① fetch   │ appcast.xml        │        │ private EdDSA key│
 │ SUPublicEDKey      │ ─────────▶ │  (versions,        │        │ (in Keychain)    │
 │ (in Info.plist)    │            │   download URL,    │        │                  │
 │                    │ ◀───────── │   signature)       │        │ signs each build │
 │ compares versions  │  ② feed    │ NotchLand-x.y.zip  │        └──────────────────┘
 │ ③ if newer: prompt │            └────────────────────┘
 │ ④ download, verify │
 │   signature, swap, │
 │   relaunch         │
 └────────────────────┘
```

1. On a schedule (or when the user clicks **Check for Updates**), the app downloads the
   `appcast.xml` from its `SUFeedURL`.
2. The appcast is an RSS feed listing the newest version, its download URL, file size, and
   an **EdDSA signature**.
3. The app compares the feed's newest **build number** (`CFBundleVersion`) to its own.
   Newer → it shows the update window with release notes.
4. The user clicks **Install** → Sparkle downloads the `.zip`, **verifies the signature**
   against the public key embedded in the app, swaps the new app in, and relaunches.

The signature is the security model: only the holder of the **private key** can produce a
signature the app accepts, so a hijacked feed cannot push a malicious build.

---

## What's already wired up ✅

- **`UpdaterController.swift`** starts `SPUStandardUpdaterController` on launch and exposes
  **Check for Updates** in the About settings pane and the menu-bar item.
- **`NotchLand/Info.plist`** carries the feed config:
  | Key | Value |
  |---|---|
  | `SUFeedURL` | `https://github.com/scienceLabwork/NotchLand/releases/latest/download/appcast.xml` |
  | `SUPublicEDKey` | `eWaZJZRPV3WMJvDk+8knSLRQqvluAsyZtzbi12lQ9Ww=` |
  | `SUEnableAutomaticChecks` | `true` |
- Auto-check has a user-facing toggle (`autoUpdateCheckEnabled`).

Because the feed URL points at `releases/latest/download/appcast.xml`, GitHub always serves
the appcast from whatever the **latest** (non-prerelease) release is.

---

## Prerequisites (one-time)

| Requirement | Status | Notes |
|---|---|---|
| **EdDSA key pair** | ✅ done | Public key is in `Info.plist`; the private key lives in your login Keychain (created via Sparkle's `generate_keys`). **Back it up.** If you lose it you can never update existing installs again. |
| **Developer ID signing** | ⚠️ required for install | Auto-update *installation* only works on a **Developer ID Application**–signed (ideally notarized) build. A development-signed build can check and download, but Sparkle will refuse to swap it in. |
| **First appcast published** | ❌ pending | Until a release contains `appcast.xml`, "Check for Updates" returns a feed error (HTTP 404). Publishing once (below) fixes it. |

### Sparkle command-line tools

The tools (`generate_appcast`, `sign_update`, `generate_keys`) are bundled by SPM under
DerivedData. Locate and add them to your `PATH`:

```bash
SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData \
  -path '*sparkle/Sparkle/bin/generate_appcast' 2>/dev/null | head -1 | xargs dirname)
export PATH="$SPARKLE_BIN:$PATH"
```

(Alternatively, download the Sparkle distribution tarball from the
[Sparkle releases page](https://github.com/sparkle-project/Sparkle/releases) — the `bin/`
folder has the same tools.)

---

## Releasing a new version (repeatable recipe)

### 1. Bump the version

In Xcode (target → General) or `NotchLand.xcodeproj/project.pbxproj`:

- `MARKETING_VERSION` — the human version, e.g. `1.0` → `1.1` (shown to users).
- `CURRENT_PROJECT_VERSION` — the **build number**, e.g. `1` → `2`.
  **This must increase every release** — Sparkle orders updates by build number.

### 2. Build a signed, exportable app

In Xcode: **Product → Archive → Distribute App → Developer ID → Export** → you get
`NotchLand.app`. Notarize it so Gatekeeper doesn't warn users:

```bash
xcrun notarytool submit NotchLand.zip --keychain-profile "AC_NOTARY" --wait
xcrun stapler staple NotchLand.app
```

### 3. Zip it and generate the appcast

```bash
mkdir -p ~/NotchLand-releases
ditto -c -k --sequesterRsrc --keepParent NotchLand.app ~/NotchLand-releases/NotchLand-1.1.zip

# Signs each build with your Keychain private key and writes appcast.xml
generate_appcast ~/NotchLand-releases \
  --download-url-prefix "https://github.com/scienceLabwork/NotchLand/releases/latest/download/"
```

`generate_appcast` writes `~/NotchLand-releases/appcast.xml` with the correct file size and
`sparkle:edSignature` for every build it finds in the folder.

### 4. Publish to GitHub Releases

Upload **both** the `.zip` and `appcast.xml` as assets on a new release:

```bash
gh release create v1.1 \
  ~/NotchLand-releases/NotchLand-1.1.zip \
  ~/NotchLand-releases/appcast.xml \
  --title "NotchLand 1.1" --notes "What's new in 1.1…"
```

Done. The feed URL serves the new `appcast.xml` from this (now latest) release, and existing
users are prompted on their next check.

---

## What the user experiences

- The app checks automatically (default ~daily) or via **Settings → About → Check for
  Updates** / the menu-bar item.
- A Sparkle window appears: *"A new version 1.1 is available — you have 1.0. Would you like
  to download it now?"* with release notes from the appcast's `<description>`.
- Click **Install** → download → signature verify → relaunch on the new version.

---

## Release notes

Release notes come from each item's `<description>` (inline HTML) in `appcast.xml`, or from
a `sparkle:releaseNotesLink` pointing at a hosted HTML file. `generate_appcast` will pick up
a matching `NotchLand-1.1.html` placed next to the `.zip` and embed/link it automatically.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| "Check for Updates" reports a feed error | No `appcast.xml` in the latest release yet. Publish step 4 once. |
| Update is found but **Install** fails or does nothing | Build isn't Developer ID–signed/notarized. Re-export via Developer ID. |
| Newer build exists but app says "up to date" | `CURRENT_PROJECT_VERSION` (build number) wasn't increased. |
| "Signature does not match" | The `.zip` was re-zipped/modified after `generate_appcast` signed it, or it was signed with a different key than `SUPublicEDKey`. Regenerate the appcast. |
| Users on old versions never see the update | The `download-url-prefix` / asset URLs in `appcast.xml` don't resolve. Confirm the `.zip` is attached to the release and the URL is correct. |

---

## Safety checklist

- [ ] Private EdDSA key backed up (lose it → no more updates, ever).
- [ ] Build number incremented.
- [ ] App is Developer ID–signed **and** notarized.
- [ ] Both `NotchLand-x.y.zip` and `appcast.xml` attached to the release.
- [ ] Installed the previous version and confirmed it updates before announcing.

---

_Maintained by Rudra Shah — Author & Creator of NotchLand._
