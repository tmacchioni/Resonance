#!/usr/bin/env python3
"""Regression test on an ephemeral GitHub runner: an existing copy must not redirect installation."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess

if os.environ.get('GITHUB_ACTIONS') != 'true':
    raise SystemExit('This system-installation test is restricted to disposable GitHub Actions runners.')
root = Path(__file__).resolve().parent.parent
config = json.loads((root / 'Config/Release.json').read_text())
dist = Path(os.environ.get('RESONANCE_DIST_DIR', root / 'dist'))
expected = Path('/Applications/Resonance.app')
if expected.exists(): raise SystemExit('Expected a clean runner without an installed Resonance app')
copy = root / '.build/installation-existing/Resonance.app'
copy.parent.mkdir(parents=True, exist_ok=True)
shutil.copytree(dist / 'Resonance.app', copy, symlinks=True)
registration = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
subprocess.run([registration, '-f', str(copy)], check=True)
subprocess.run(['sudo', '/usr/sbin/installer', '-pkg', str(dist / f'Resonance-{config["version"]}-universal.pkg'), '-target', '/'], check=True)
if not expected.is_dir(): raise SystemExit('Installer relocated the app instead of installing to /Applications')
info = plistlib.loads((expected / 'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == config['bundle_id']
assert info['CFBundleShortVersionString'] == config['version']
assert copy.is_dir(), 'The pre-existing development copy should remain available'
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(expected)], check=True)
print('PASS: installer targets /Applications even with another registered app copy present.')
