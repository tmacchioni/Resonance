#!/usr/bin/env python3
"""Small JavaScript runtime, compiled for the application's macOS deployment target."""
import os
import json
from pathlib import Path
import shutil
import subprocess
from dependency_manifest import Manifest

root = Path(__file__).resolve().parent.parent
manifest = Manifest()
source = manifest.extract_source('quickjs-ng')
release = json.loads((root / 'Config/Release.json').read_text())
recipe = manifest.fingerprint(['quickjs-ng'], Path(__file__).read_bytes() + release['minimum_macos'].encode())
for arch in ['arm64', 'x86_64']:
    output = root / '.build/quickjs' / arch / recipe
    subprocess.run(['cmake', '-S', str(source), '-B', str(output), '-DCMAKE_BUILD_TYPE=MinSizeRel',
                    f'-DCMAKE_OSX_ARCHITECTURES={arch}', f'-DCMAKE_OSX_DEPLOYMENT_TARGET={release["minimum_macos"]}',
                    '-DQJS_BUILD_EXAMPLES=OFF', '-DQJS_BUILD_CLI_STATIC=OFF'], check=True)
    subprocess.run(['cmake', '--build', str(output), '--target', 'qjs_exe', '-j', str(min(os.cpu_count() or 4, 8))], check=True)
    target = root / 'vendor/bin' / arch / 'qjs'
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(output / 'qjs', target)
    subprocess.run(['strip', '-x', str(target)], check=True)
shutil.copy2(source / 'LICENSE', root / 'vendor/licenses/QuickJS-MIT.txt')
