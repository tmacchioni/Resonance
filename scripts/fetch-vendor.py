#!/usr/bin/env python3
"""Fetch pinned standalone tools. No Python packages required."""
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
from dependency_manifest import Manifest, file_sha256

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / 'vendor/cache'

def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    manifest = Manifest()
    for name, asset in manifest.dependencies.items():
        target = manifest.cache_path(name)
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists():
            # Reuse the old flat cache only when its bytes match the new pin.
            legacy = CACHE / asset.file
            with tempfile.TemporaryDirectory(dir=target.parent) as directory:
                pending = Path(directory) / 'download'
                if legacy.is_file() and file_sha256(legacy) == asset.sha256:
                    shutil.copy2(legacy, pending)
                else:
                    subprocess.run(['curl', '--location', '--fail', '--show-error', '--retry', '2', asset.url, '-o', str(pending)], check=True)
                if file_sha256(pending) != asset.sha256:
                    raise SystemExit(f'Checksum mismatch for {asset.file}. File not installed.')
                pending.rename(target)
        manifest.verified_archive(name)
        print(asset.file, 'verified', flush=True)
    for arch in ['arm64', 'x86_64']:
        folder = ROOT / 'vendor/bin' / arch
        folder.mkdir(parents=True, exist_ok=True)
        shutil.copy2(manifest.verified_archive('yt-dlp'), folder / 'yt-dlp')
        (folder / 'yt-dlp').chmod(0o755)
    sparkle = ROOT / 'vendor/sparkle'
    with tempfile.TemporaryDirectory(dir=sparkle.parent) as directory:
        staging = Path(directory) / 'sparkle'
        staging.mkdir()
        with tarfile.open(manifest.verified_archive('sparkle')) as archive:
            archive.extractall(staging, filter='data')
        if not (staging / 'Sparkle.framework').is_dir(): raise SystemExit('Sparkle archive is missing its framework')
        if sparkle.exists(): shutil.rmtree(sparkle)
        staging.rename(sparkle)

if __name__ == '__main__': main()
