# Updating dependencies / Aggiornare le dipendenze

`vendor/manifest.json` is the only place to edit dependency versions, download URLs, archive names, source directories and SHA-256 pins. Build and packaging scripts do not contain their own version numbers. `Package.swift` also reads Sparkle's version directly from this catalog.

## Procedura

1. Cambia la versione del componente in `versions`.
2. Cambia il suo `sha256` nell’elemento corrispondente di `assets`, confrontandolo con quello ufficiale quando disponibile. Il checksum deve riferirsi esattamente all’archivio o eseguibile indicato.
3. I campi `file`, `url` e `source_directory` sostituiscono automaticamente `{version}`. Se il fornitore cambia lo schema dei nomi o la struttura dell’archivio, adatta quei campi nello stesso manifest.
4. Controlla note di rilascio, compatibilità e licenze del componente. Un cambiamento incompatibile può comunque richiedere modifiche al codice o alle opzioni di compilazione.
5. Esegui i controlli e pubblica le modifiche. La CI ripete compilazione e test su un runner pulito.

```sh
python3 scripts/dependency_manifest.py
python3 -m unittest discover -s Tests -p 'test_*.py'
python3 scripts/fetch-vendor.py
python3 scripts/build-media.py
python3 scripts/build-runtime.py
python3 scripts/check-project.py
python3 scripts/test.py
python3 scripts/build.py
python3 scripts/verify-package.py
```

Non occorre cancellare manualmente la cache quando cambia una dipendenza. I download sono archiviati per checksum; le cartelle di compilazione dipendono dalla versione, dai sorgenti, dalla ricetta e dal target macOS. Per LAME e Opus questo evita di riutilizzare vecchie librerie statiche dopo un aggiornamento.

Per distribuire l’aggiornamento, incrementa versione e numero build dell’app in `Config/Release.json`, aggiorna le note e pubblica il nuovo tag come descritto in [RELEASING.md](RELEASING.md). Gli utenti riceveranno una nuova versione completa dell’app, con i motori aggiornati.

## Validation and generated records

The shared loader rejects missing/duplicate components, invalid checksums, non-HTTPS URLs, unknown template fields and unsafe paths. Archives are verified before extraction, and source directory layouts are checked. A bad download is not promoted to the cache or installed.

Packaged apps include a generated `Licenses/Dependencies.json` with resolved component versions, hashes and download URLs. Release source archives include the same manifest and shared build helper, so they follow the selected dependencies automatically.

Dependabot handles GitHub Actions. The Swift manifest intentionally reads a dynamic version from the shared catalog; Sparkle must be updated through the catalog together with its pinned binary archive, not by an independent Dependabot edit to `Package.swift`.
