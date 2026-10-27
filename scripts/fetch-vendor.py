#!/usr/bin/env python3
"""Fetch pinned standalone tools. No Python packages required."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile
import tarfile

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / 'vendor/cache'

def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((ROOT / 'vendor/manifest.json').read_text())
    for asset in manifest['assets']:
        target = CACHE / asset['file']
        if not target.exists():
            subprocess.run(['curl', '--location', '--fail', '--show-error', '--retry', '2', asset['url'], '-o', str(target)], check=True)
        digest = hashlib.file_digest(target.open('rb'), 'sha256').hexdigest()
        if digest != asset['sha256']:
            raise SystemExit(f'Checksum mismatch for {target}. File not installed.')
        print(asset['file'], 'verified', flush=True)
    for arch in ['arm64', 'x86_64']:
        folder = ROOT / 'vendor/bin' / arch
        folder.mkdir(parents=True, exist_ok=True)
        shutil.copy2(CACHE / 'yt-dlp', folder / 'yt-dlp')
        (folder / 'yt-dlp').chmod(0o755)
    sparkle = ROOT / 'vendor/sparkle'
    sparkle.mkdir(exist_ok=True)
    with tarfile.open(CACHE / 'Sparkle-2.10.1.tar.xz') as archive:
        # Official macOS framework uses symlinks; extraction is limited to a pinned, verified archive.
        archive.extractall(sparkle, filter='tar')

if __name__ == '__main__': main()
