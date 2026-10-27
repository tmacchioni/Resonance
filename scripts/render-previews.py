#!/usr/bin/env python3
"""Render the actual views in an isolated preview app, without capturing other windows."""
from pathlib import Path
import plistlib
import shutil
import subprocess

root = Path(__file__).resolve().parent.parent
app = root / '.build/ResonancePreview.app'
executable = app / 'Contents/MacOS/Preview'
executable.parent.mkdir(parents=True, exist_ok=True)
resources = app / 'Contents/Resources'
resources.mkdir(exist_ok=True)
frameworks = app / 'Contents/Frameworks'
frameworks.mkdir(exist_ok=True)
if not (frameworks / 'Sparkle.framework').exists():
    (frameworks / 'Sparkle.framework').symlink_to(root / 'vendor/sparkle/Sparkle.framework')
config = {'CFBundleIdentifier': 'it.resonance.preview', 'CFBundleExecutable': 'Preview', 'CFBundleDevelopmentRegion': 'en', 'CFBundleLocalizations': ['en', 'it'], 'CFBundleShortVersionString': '1.1.0'}
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps(config))
for lang in ['en', 'it']:
    shutil.copytree(root / f'Sources/Resonance/Resources/{lang}.lproj', resources / f'{lang}.lproj', dirs_exist_ok=True)
sources = sorted(p for p in (root / 'Sources/Resonance').glob('*.swift') if p.name != 'ResonanceApp.swift')
subprocess.run(['swiftc', '-parse-as-library', '-O', '-swift-version', '5', '-F', str(root / 'vendor/sparkle'),
                '-framework', 'Sparkle', '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks',
                *map(str, sources), str(root / 'scripts/render-preview.swift'), '-o', str(executable)], check=True)
screenshots = root / 'docs/images'
screenshots.mkdir(exist_ok=True)
for lang in ['en', 'it']:
    subprocess.run([str(executable), str(screenshots / f'resonance-{lang}.png'), lang], check=True, timeout=20)
