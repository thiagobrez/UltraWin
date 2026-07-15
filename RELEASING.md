# Releasing UltraWin

Releases are automated with [changesets](https://github.com/changesets/changesets)
and GitHub Actions. Every release produces:

- a **git tag** `vX.Y.Z` and a **GitHub Release** with changelog notes,
- a signed, notarized, stapled **DMG** attached to the release
  (plus an unversioned `UltraWin.dmg` copy so
  `https://github.com/thiagobrez/UltraWin/releases/latest/download/UltraWin.dmg`
  always points at the latest version),
- an updated **Sparkle appcast** (`docs/appcast.xml`, committed to `master`
  and served by GitHub Pages at
  `https://thiagobrez.github.io/UltraWin/appcast.xml`) so existing
  installs auto-update,
- an updated **Homebrew cask** in
  [thiagobrez/homebrew-tap](https://github.com/thiagobrez/homebrew-tap)
  (`brew install thiagobrez/tap/ultrawin`), pointing at the same DMG.

There is no App Store channel: UltraWin relies on the private
`CGVirtualDisplay` API and runs unsandboxed, both of which App Review
rejects. Notarization, however, is only a malware scan and accepts the
app fine (same situation as DeskPad and BetterDisplay).

## Day-to-day flow

1. In any PR with user-visible changes, run `npx changeset`, pick
   patch/minor/major, write a short summary, and commit the generated
   `.changeset/*.md` file.
2. Merge to `master`. The **Release** workflow opens/updates a
   `chore: release` PR ("Version Packages") that bumps `package.json`,
   `project.yml` (`MARKETING_VERSION`, via `scripts/sync-version.sh`) and
   `CHANGELOG.md`.
3. Merge that PR when you want to cut the release. The workflow tags, creates
   the GitHub Release, and the **Build & Publish** workflow (same run) builds,
   notarizes and attaches the DMG.

Commits without changesets never trigger a release.

## Version / build number rules

- `package.json` is the **source of truth** for the marketing version. Never
  hand-edit `MARKETING_VERSION` in `project.yml` — `scripts/sync-version.sh`
  overwrites it.
- The build number (`CURRENT_PROJECT_VERSION`) is injected at build time as
  `git rev-list --count HEAD` (override with the `build-number` input when
  re-dispatching).
- `UltraWin.xcodeproj` is gitignored; CI always runs `xcodegen generate`
  first. Run it locally too before archiving by hand.

## Automatic updates (Sparkle)

Builds self-update via [Sparkle](https://sparkle-project.org): the app polls
`https://thiagobrez.github.io/UltraWin/appcast.xml`, which the
**Build & Publish** workflow regenerates and commits to `docs/` on `master`
after notarizing each release DMG. Every appcast item is EdDSA-signed.

One-time setup (already done if `SUPublicEDKey` in `UltraWin/Info.plist`
holds a real key):

1. Download the Sparkle distribution matching `SPARKLE_TOOLS_VERSION` in
   `release-build.yml` and run `./bin/generate_keys`. Paste the printed
   **public** key into `UltraWin/Info.plist` → `SUPublicEDKey` (safe to
   commit).
2. Export the private key with `./bin/generate_keys -x /tmp/sparkle_key`, add
   the file's contents as the `SPARKLE_ED_PRIVATE_KEY` repo secret, then
   delete the file. Losing this key means shipped apps reject future updates,
   so keep the Keychain copy backed up.

Notes:

- Keep `SPARKLE_TOOLS_VERSION` in `release-build.yml` in sync with the Sparkle
  package version in `project.yml`.
- Do not reuse another app's key pair — generate a fresh one per app.

## Homebrew tap

`brew install thiagobrez/tap/ultrawin` installs the release DMG. The **Build &
Publish** workflow regenerates `Casks/ultrawin.rb` in
[thiagobrez/homebrew-tap](https://github.com/thiagobrez/homebrew-tap) from the
template in `scripts/update-homebrew-cask.sh` and pushes it directly to the
tap's `main` — never edit the cask in the tap repo by hand.

The push authenticates with the `HOMEBREW_TAP_TOKEN` repo secret: a
fine-grained PAT scoped to the `homebrew-tap` repository with **Contents:
read and write**. When it expires, mint a new one at
GitHub → Settings → Developer settings → Fine-grained tokens and update the
secret.

## Analytics

Anonymous usage analytics go through TelemetryDeck. The app ID is injected at
build time from `Config/Analytics.local.xcconfig` (locally) or the
`TELEMETRYDECK_APP_ID` repo secret (CI). Without it the app builds fine and
analytics stays off.

## One-time repo setup

- Enable GitHub Pages: Settings → Pages → deploy from `master` / `docs/`.
- Settings → Actions → General: workflow permissions **Read and write**, and
  allow GitHub Actions to **create and approve pull requests** (required by
  changesets/action).

## Required repo secrets

`APPLE_TEAM_ID`, `DEVELOPER_ID_APPLICATION_P12_BASE64`,
`DEVELOPER_ID_APPLICATION_P12_PASSWORD`, `APP_STORE_CONNECT_API_KEY_ID`,
`APP_STORE_CONNECT_API_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8_BASE64`
(App Store Connect key is used only for notarization),
`TELEMETRYDECK_APP_ID`, `SPARKLE_ED_PRIVATE_KEY`, `HOMEBREW_TAP_TOKEN`.
