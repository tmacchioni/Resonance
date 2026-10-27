# Releasing Resonance

## Version and repository configuration

Edit `Config/Release.json`: semantic `version`, strictly increasing numeric `build`, repository and minimum macOS version. The app uses `https://github.com/OWNER/REPO/releases/latest/download/appcast.xml`. Only stable, published releases should become latest.

Forks must generate their own update key and change the repository before distribution. Do not point a modified fork at the upstream update feed.

## Update signing key

`Config/UpdatePublicKey.txt` is public and is embedded in the app. The matching private seed is excluded from Git and stored locally in `.private/sparkle-private-key`. Back it up securely: losing it prevents existing installations from trusting new archives signed with another key.

For a new fork, generate a fresh key after removing the inherited public key:

```sh
swift scripts/generate-update-key.swift "$PWD"
gh secret set SPARKLE_PRIVATE_KEY --repo OWNER/REPO < .private/sparkle-private-key
```

Do not regenerate an established project's key to fix a build error. Never put the private seed in source, release assets, issue reports or command arguments. Sparkle receives the key from a protected file.

## Automated releases

For external component updates, follow [DEPENDENCIES.md](DEPENDENCIES.md). Dependency versions have one source of truth in `vendor/manifest.json`.

The `Publish release` workflow runs on `v*` tags. It checks that the tag matches the configured version, builds dependencies from pinned source archives, tests all formats, builds the universal app, creates and verifies Ed25519 archive signatures, signs the feed, packages corresponding sources, uploads all artifacts to a draft release, then publishes it as latest.

```sh
git tag v1.2.0
git push origin v1.2.0
```

Before tagging, update release notes and configuration, run the checks and review the final diff. The workflow needs the `SPARKLE_PRIVATE_KEY` repository secret. Untrusted pull requests never receive signing secrets.

The source archive must remain attached to every binary release. Preserve previous releases so users can retrieve the sources corresponding to their installed version. yt-dlp and Sparkle retain their upstream licenses and bundled notices; their pinned source repositories are linked in the README and notice file.

## Apple Developer ID and notarization

Sparkle signatures authenticate updates; they do not remove Gatekeeper warnings. For a normal notarized public distribution configure:

- Secrets: `APPLE_CERTIFICATES_BASE64` (P12 containing Application and Installer identities), `APPLE_CERTIFICATE_PASSWORD`.
- Variables: `APPLE_SIGN_IDENTITY`, `APPLE_INSTALLER_IDENTITY` (the full identity names).
- Secrets for notarization: `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`.

The workflow imports credentials into an ephemeral keychain, signs nested helpers and frameworks, notarizes/staples the app and installer, and removes the keychain afterwards. The initial release has no Developer ID credentials and is clearly labeled ad hoc / not notarized. Update the release notes when enabling notarization.

For local release builds the corresponding environment variables are `RESONANCE_SIGN_IDENTITY`, `RESONANCE_INSTALLER_IDENTITY`, and optionally `RESONANCE_NOTARY_PROFILE` (a previously configured notarytool keychain profile).

## Local verification

```sh
python3 scripts/check-project.py
python3 scripts/test.py
python3 scripts/build.py
python3 scripts/verify-package.py
python3 scripts/prepare-release.py
python3 scripts/verify-release.py
```

The verification checks both architectures, macOS deployment targets, framework presence, system-only media dependencies, update configuration, locales, archive signature and rejection of a modified archive. Test an actual old-to-new installation on a disposable app copy before major updater changes. Do not overwrite the published assets of an existing release with different bytes.
