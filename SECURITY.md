# Security

Do not post credentials, private playlist links, session captures or signing keys in an issue. Use the repository's private vulnerability reporting feature when available.

Updates use Sparkle with an embedded Ed25519 public key. Archives are verified before extraction, the feed is signed, and installation requires user confirmation. The private update key is held outside the repository and in a GitHub Actions secret. Apple Developer ID signing and notarization are separate from Sparkle signatures; ad-hoc builds are explicitly identified in release notes.

Report suspected update-validation failures, unsafe process argument handling or unexpected external connections privately before public disclosure. Download engines change frequently; maintainers may ask you to reproduce with the current release.
