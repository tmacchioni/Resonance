# Contributing

Resonance welcomes focused bug reports, translations and pull requests. Please describe a reproducible problem before proposing a large change.

Build instructions are in [README.md](README.md). Run `python3 scripts/check-project.py` and `python3 scripts/test.py` before submitting changes. For packaging changes, also run the build and package verification scripts.

For build/dependency changes, also run `python3 -m unittest discover -s Tests -p 'test_*.py'`. Follow [DEPENDENCIES.md](docs/DEPENDENCIES.md); use the manifest's version templates instead of adding version numbers to scripts.

Edit translations in `Config/English.json`, then run `python3 scripts/generate-localizations.py`. Italian keys are the original UI messages; both native `.strings` tables are generated from the catalog. Do not translate track titles, artists or third-party diagnostic output.

Dependency changes must update `vendor/manifest.json`, keep hashes pinned, include applicable licenses and keep the corresponding-source release archive complete. Preserve compatibility with macOS 13, Intel and Apple Silicon. The runtime must remain self-contained.

Do not commit credentials, update signing keys, downloaded media, personal history, session captures or build outputs. Contributions are licensed under GPL-3.0-or-later, like the project.

Please be respectful and discuss the work rather than the person.
