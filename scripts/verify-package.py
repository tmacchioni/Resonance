#!/usr/bin/env python3
"""Check bundle architectures, OS targets, signatures, dependencies and installer."""
from pathlib import Path
import json
import base64
import plistlib
import re
import subprocess
import tempfile
import os
import xml.etree.ElementTree as ET
from dependency_manifest import Manifest

root = Path(__file__).resolve().parent.parent
dist = Path(os.environ.get('RESONANCE_DIST_DIR', root / 'dist'))
app = dist / 'Resonance.app'
tools = app / 'Contents/Resources/Tools'
config = json.loads((root / 'Config/Release.json').read_text())
pkg = dist / f'Resonance-{config["version"]}-universal.pkg'

def output(*args): return subprocess.check_output([str(a) for a in args], text=True)

info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert info['LSMinimumSystemVersion'] == '13.0'
assert info['CFBundleVersion'] == config['build']
assert info['SUFeedURL'] == f'https://github.com/{config["repository"]}/releases/latest/download/appcast.xml'
assert len(base64.b64decode(info['SUPublicEDKey'])) == 32
assert info['SUAllowsAutomaticUpdates'] is False
assert info['SUAutomaticallyUpdate'] is False
assert info['SUVerifyUpdateBeforeExtraction'] is True
assert info['SURequireSignedFeed'] is True
for language in ['it', 'en']:
    assert (app / f'Contents/Resources/{language}.lproj/Localizable.strings').is_file()
assert (app / 'Contents/Frameworks/Sparkle.framework').is_dir()
inventory = json.loads((app / 'Contents/Resources/Licenses/Dependencies.json').read_text())
assert inventory == Manifest().resolved(), 'Packaged dependencies must match the manifest'
assert not any(path.name == 'deno' for path in tools.rglob('*'))
assert set(output('lipo', '-archs', app / 'Contents/MacOS/Resonance').split()) == {'arm64', 'x86_64'}
for arch in ['arm64', 'x86_64']:
    for name in ['ffmpeg', 'ffprobe', 'qjs', 'yt-dlp']:
        path = tools / arch / name
        assert path.exists(), path
        assert arch in output('lipo', '-archs', path).split(), path
        linked = output('otool', '-L', path)
        for line in linked.splitlines():
            if 'compatibility version' in line:
                dependency = line.strip().split(' (')[0]
                assert dependency.startswith(('/System/', '/usr/lib/')), (path, dependency)
        load_commands = output('otool', '-arch', arch, '-l', path)
        versions = re.findall(r'\b(?:minos|version) (\d+)\.(\d+)', load_commands)
        assert versions and tuple(map(int, versions[0])) <= (13, 0), (path, versions)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
with tempfile.TemporaryDirectory(prefix='resonance-pkg-check-') as folder:
    expanded = Path(folder) / 'expanded'
    subprocess.run(['pkgutil', '--expand', str(pkg), str(expanded)], check=True)
    xml = (expanded / 'Distribution').read_text()
    assert 'min="13.0"' in xml
    assert 'arm64,x86_64' in xml
    assert (expanded / 'Resonance-component.pkg/Payload').exists()
    package_info = ET.parse(expanded / 'Resonance-component.pkg/PackageInfo')
    assert package_info.getroot().get('install-location') == '/'
    assert not package_info.findall('.//relocate/bundle'), 'Installer must not relocate existing app copies'
print('PASS: universal app, bundled tools, signatures and installer pinned to /Applications without relocation.')
