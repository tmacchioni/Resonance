#!/usr/bin/env python3
"""Verify update signatures independently with the public key shipped in the app."""
import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET
import tarfile
from dependency_manifest import Manifest, SOURCE_COMPONENTS

root = Path(__file__).resolve().parent.parent
config = json.loads((root / 'Config/Release.json').read_text())
dist = root / 'dist'
tree = ET.parse(dist / 'appcast.xml')
ns = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
item = tree.find('./channel/item')
assert item.findtext('sparkle:version', namespaces=ns) == config['build']
enclosure = item.find('enclosure')
archive = dist / f'Resonance-{config["version"]}-universal.zip'
assert enclosure.attrib['url'] == f'https://github.com/{config["repository"]}/releases/download/v{config["version"]}/{archive.name}'
assert int(enclosure.attrib['length']) == archive.stat().st_size
signature = enclosure.attrib[f'{{{ns["sparkle"]}}}edSignature']
assert len(base64.b64decode(signature)) == 64
checker = root / '.build/verify-signature'
subprocess.run(['swiftc', str(root / 'scripts/verify-signature.swift'), '-o', str(checker)], check=True)
subprocess.run([str(checker), str(archive), str(root / 'Config/UpdatePublicKey.txt'), signature], check=True)
tampered = root / '.build/tampered-update'
tampered.write_bytes(b'tampered update')
result = subprocess.run([str(checker), str(tampered), str(root / 'Config/UpdatePublicKey.txt'), signature], capture_output=True)
assert result.returncode == 1, 'Tampered archives must be rejected'
tampered.unlink()
key = Path(os.environ.get('SPARKLE_KEY_FILE', root / '.private/sparkle-private-key'))
if key.exists():
    subprocess.run([str(root / 'vendor/sparkle/bin/sign_update'), '--verify', '--ed-key-file', str(key), str(dist / 'appcast.xml')], check=True)
for line in (dist / 'SHA256SUMS.txt').read_text().splitlines():
    digest, filename = line.split('  ', 1)
    assert hashlib.file_digest((dist / filename).open('rb'), 'sha256').hexdigest() == digest
manifest = Manifest()
with tarfile.open(dist / f'Resonance-{config["version"]}-third-party-sources.tar.xz') as sources:
    for name in SOURCE_COMPONENTS:
        member = str(manifest.cache_path(name).relative_to(root))
        with sources.extractfile(member) as data:
            assert hashlib.file_digest(data, 'sha256').hexdigest() == manifest.get(name).sha256
    for required in ['scripts/dependency_manifest.py', 'vendor/manifest.json', 'Config/Release.json']:
        assert sources.getmember(required).isfile()
print('PASS: signed archive, tamper rejection, signed appcast, versions, URLs, checksums and corresponding sources.')
