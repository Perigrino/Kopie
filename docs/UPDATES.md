# Updates

Kopie updates itself with [Sparkle 2](https://sparkle-project.org). This is the
only third-party dependency. It is used as a library plus Sparkle's standard
native update panel; no update UI is reimplemented here.

This document covers **Phase 1**: free development and update testing with
ad-hoc signing. Phase 2 (a personal Apple Developer membership, Developer ID
signing, and notarization) is intentionally not configured yet.

## How it works

1. Sparkle reads `SUFeedURL` from `Info.plist`
   (`https://perigrino.github.io/Kopie/appcast.xml`) and checks it at most once
   a day (`SUScheduledCheckInterval` = 86400). Manual checks are always
   available from **Settings → General → Software Update** and the menu-bar
   menu.
2. Each appcast item points at a versioned DMG attached to a **GitHub Release**
   and at a release-notes Markdown file next to it. GitHub Pages hosts only
   `appcast.xml`. Nothing in the app bundle contains a token or signing key.
3. Before installing, Sparkle verifies the archive's Ed25519 signature against
   `SUPublicEDKey`, then verifies the new app's code signature. A downloaded
   update therefore cannot be substituted by a compromised CDN.
4. The standard panel offers **Install**, **Remind Me Later**, and **Skip This
   Version**; Sparkle persists the choice, so the same version is not raised
   again after it is skipped.

Release notes are not duplicated: the workflow extracts the matching
`## <version>` section from `CHANGELOG.md`, uploads it with the DMG, and links
it from the appcast.

The appcast carries the latest release only; version history and older
downloads remain on GitHub Releases. This is sufficient while every release
supports macOS 13+ and arm64.

## Phase 1 signing status (read this before distributing)

Phase 1 builds are **ad-hoc signed and not notarized**. They are suitable for
development and update testing, not for claiming production-grade distribution.

- **First download:** Gatekeeper may block the DMG ("Apple could not verify
  …"). Open it with right-click → **Open**, or allow it in **System Settings →
  Privacy & Security → Open Anyway**. Do not disable Gatekeeper globally.
- `spctl --assess` rejects the app by design. `codesign --verify` passes.
- **In-app updates:** Sparkle verifies EdDSA plus the pinned designated
  requirement (`identifier "com.kopie.app"`) and releases the quarantine flag
  before installing, so updates it installs should launch without repeating the
  first-download warning. Validate this with two consecutive versions on the
  target Mac before relying on it.
- **Accessibility grant:** the designated requirement is pinned to the bundle
  identifier, so the TCC grant should survive rebuilds and Sparkle updates.
  Verify it after an update.
- **Existing users:** 2.5.0/2.6 have no updater. The first Sparkle-enabled build
  must be downloaded and installed manually once; later versions can arrive
  in-app.
- **Architecture:** releases are arm64-only, matching the existing app. Intel
  Macs are not supported.
- **Not included yet:** gentle background reminders for the menu-bar app.
  Scheduled checks use Sparkle's standard panel; a quiet notification/badge is
  Phase 1 polish. Developer ID signing and notarization are Phase 2.

## Release checklist

1. Bump `version` in `package.json` (for example `2.7.0`). This is the only
   place the marketing version lives; `scripts/build.sh` stamps it into
   `Info.plist`.
2. Add a matching `## 2.7.0 — <date>` section to `CHANGELOG.md`.
3. Commit, then tag and push:

   ```bash
   git tag v2.7.0
   git push origin main v2.7.0
   ```

The release workflow refuses a tag that does not match `package.json`. It then
builds (`CFBundleVersion` = `git rev-list --count HEAD`), creates the GitHub
Release with the versioned DMG and notes, signs the appcast, and pushes only
`appcast.xml` to `gh-pages`.

`CFBundleVersion` must only ever go up. Commit count is monotonic for a normal
linear history; avoid force-pushing or reusing a tag once a release is public.

## One-time infrastructure

- **GitHub Pages** — Settings → Pages → *Deploy from a branch* → `gh-pages` /
  `/ (root)`. The first release creates that branch. The feed is then at
  `https://perigrino.github.io/Kopie/appcast.xml`. Enable Pages after the first
  release; the workflow can create the branch before Pages is switched on.
- **Signing key** — the public half is committed at
  `scripts/sparkle-public-key.txt` and stamped into `Info.plist` as
  `SUPublicEDKey`. The private half is `.sparkle-private-key` (gitignored,
  mode `600`) and must be stored as a repository secret:

  ```bash
  gh secret set SPARKLE_PRIVATE_KEY < .sparkle-private-key
  ```

  Back the private key up somewhere safe. If it is lost, a build signed with a
  new key cannot update existing installs (the old app only trusts the old
  public key), so a key rotation needs one manually downloaded release first.

No Apple Developer credentials are required for Phase 1, and none are
configured in the workflow.

## Verifying a release locally

```bash
curl -fsSL https://perigrino.github.io/Kopie/appcast.xml
# Download the DMG from the URL in the enclosure element, then:
./Sparkle-2.10.1/bin/sign_update --verify \
  --ed-key-file .sparkle-private-key \
  Kopie-2.7.0.dmg "<edSignature from the appcast>"
```

Also check that the appcast's enclosure URL and release-notes URL point at
`github.com/Perigrino/Kopie/releases/download/vX.Y.Z/…`, and that the DMG name,
`CFBundleShortVersionString`, and tag all agree.

## Withdrawing a release

Sparkle cannot downgrade an installed app. To stop offering a bad build, remove
its item from the appcast (or publish a corrected, higher version) and re-run
the appcast publication. Mark the GitHub Release as a pre-release or delete its
asset if it should no longer be downloaded manually. For a security issue, use
Sparkle's critical-update marking in a superseding release.

## Testing an update without publishing

Build and install version A, then build version B with a higher
`package.json` version and a higher `KOPIE_BUILD_NUMBER`, and serve B's DMG plus
a locally generated appcast over HTTPS. Sparkle requires the feed to be HTTPS;
a local TLS proxy or tunnel is the quickest way to test the full install path
without touching the public feed.
