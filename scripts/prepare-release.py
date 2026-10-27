#!/usr/bin/env python3
"""Create a signed GitHub-hosted Sparkle feed and corresponding-source archive."""
import email.utils
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tarfile
import xml.etree.ElementTree as ET
from dependency_manifest import Manifest, SOURCE_COMPONENTS

ROOT = Path(__file__).resolve().parent.parent
SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE)

def prepare():
    config = json.loads((ROOT / 'Config/Release.json').read_text())
    repo = os.environ.get('RESONANCE_REPOSITORY', config['repository'])
    version = config['version']
    tag = f'v{version}'
    key = Path(os.environ.get('SPARKLE_KEY_FILE', ROOT / '.private/sparkle-private-key'))
    if not key.is_file(): raise SystemExit('Provide SPARKLE_KEY_FILE. Never commit the private signing key.')
    signer = ROOT / 'vendor/sparkle/bin/sign_update'
    dist = Path(os.environ.get('RESONANCE_DIST_DIR', ROOT / 'dist'))
    archive = dist / f'Resonance-{version}-universal.zip'
    signature = subprocess.check_output([str(signer), '--ed-key-file', str(key), '-p', str(archive)], text=True).strip()
    rss = ET.Element('rss', version='2.0')
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'Resonance updates'
    ET.SubElement(channel, 'link').text = f'https://github.com/{repo}/releases'
    ET.SubElement(channel, 'description').text = 'Stable releases of Resonance for macOS'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f'Resonance {version}'
    ET.SubElement(item, 'pubDate').text = email.utils.formatdate(usegmt=True)
    ET.SubElement(item, f'{{{SPARKLE}}}version').text = config['build']
    ET.SubElement(item, f'{{{SPARKLE}}}shortVersionString').text = version
    ET.SubElement(item, f'{{{SPARKLE}}}minimumSystemVersion').text = config['minimum_macos']
    ET.SubElement(item, 'description').text = f'See https://github.com/{repo}/releases/tag/{tag} for release notes.'
    ET.SubElement(item, 'enclosure', {
        'url': f'https://github.com/{repo}/releases/download/{tag}/{archive.name}',
        'length': str(archive.stat().st_size), 'type': 'application/octet-stream',
        f'{{{SPARKLE}}}edSignature': signature,
    })
    feed = dist / 'appcast.xml'
    ET.indent(rss)
    ET.ElementTree(rss).write(feed, encoding='utf-8', xml_declaration=True)
    subprocess.run([str(signer), '--ed-key-file', str(key), str(feed)], check=True)
    sources = dist / f'Resonance-{version}-third-party-sources.tar.xz'
    with tarfile.open(sources, 'w:xz') as tar:
        # Include all source inputs, licenses and exact build recipes for the media tools.
        manifest = Manifest()
        for name in SOURCE_COMPONENTS:
            tar.add(manifest.verified_archive(name), arcname=str(manifest.cache_path(name).relative_to(ROOT)))
        for path in [ROOT / 'vendor/manifest.json', ROOT / 'Config/Release.json', ROOT / 'vendor/licenses', ROOT / 'scripts/build-media.py', ROOT / 'scripts/build-runtime.py', ROOT / 'scripts/dependency_manifest.py', ROOT / 'scripts/fetch-vendor.py']:
            tar.add(path, arcname=str(path.relative_to(ROOT)))
    artifacts = [archive, sources, feed, dist / f'Resonance-{version}-universal.pkg']
    (dist / 'SHA256SUMS.txt').write_text(''.join(f'{hashlib.file_digest(path.open("rb"), "sha256").hexdigest()}  {path.name}\n' for path in artifacts))
    print('Signed appcast and source archive ready. The private key was not copied into distribution files.')

if __name__ == '__main__': prepare()
