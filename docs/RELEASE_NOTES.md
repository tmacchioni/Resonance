## Resonance 1.1.3

- Fixed the package installer updating an existing app in Downloads instead of installing to `/Applications/Resonance.app`.
- Disabled bundle relocation for the app and its nested Sparkle helpers.
- Added a check of the generated package metadata to prevent this installation-path regression.

Existing installations can update directly to v1.1.3. To correct an app installed outside Applications by an older package, install the v1.1.3 package.

macOS 13 or later, Intel and Apple Silicon. All runtime components are included.

This release is signed ad hoc, not with Apple Developer ID, and is not notarized. Gatekeeper may require explicit approval in System Settings → Privacy & Security. Do not disable system protection globally. Sparkle update signatures still verify the origin and integrity of update files.

Spotify supplies public metadata; matching audio comes from YouTube and may be a different recording. Public Spotify previews may contain only part of a playlist. Only download content you own or are authorized to download.
