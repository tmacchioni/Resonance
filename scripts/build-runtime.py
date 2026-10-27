#!/usr/bin/env python3
"""Small JavaScript runtime, compiled for the application's macOS deployment target."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile

root = Path(__file__).resolve().parent.parent
asset = next(a for a in json.loads((root / 'vendor/manifest.json').read_text())['assets'] if a['file'].startswith('quickjs-'))
archive = root / 'vendor/cache' / asset['file']
assert hashlib.file_digest(archive.open('rb'), 'sha256').hexdigest() == asset['sha256']
sources = root / 'vendor/sources'
sources.mkdir(exist_ok=True)
with tarfile.open(archive) as tar:
    tar.extractall(sources, filter='data')
source = sources / 'quickjs-0.17.0'
for arch in ['arm64', 'x86_64']:
    output = root / '.build/quickjs' / arch
    subprocess.run(['cmake', '-S', str(source), '-B', str(output), '-DCMAKE_BUILD_TYPE=MinSizeRel',
                    f'-DCMAKE_OSX_ARCHITECTURES={arch}', '-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0',
                    '-DQJS_BUILD_EXAMPLES=OFF', '-DQJS_BUILD_CLI_STATIC=OFF'], check=True)
    subprocess.run(['cmake', '--build', str(output), '--target', 'qjs_exe', '-j', str(min(os.cpu_count() or 4, 8))], check=True)
    target = root / 'vendor/bin' / arch / 'qjs'
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(output / 'qjs', target)
    subprocess.run(['strip', '-x', str(target)], check=True)
shutil.copy2(source / 'LICENSE', root / 'vendor/licenses/QuickJS-MIT.txt')
