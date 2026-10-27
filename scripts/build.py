#!/usr/bin/env python3
"""Build a self-contained universal app, installer and Sparkle update archive."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
from dependency_manifest import Manifest

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / 'dist'
BUILD = ROOT / '.build/distribution'
APP = BUILD / 'root/Applications/Resonance.app'
RESOURCES = APP / 'Contents/Resources'
IDENTITY = os.environ.get('RESONANCE_SIGN_IDENTITY', '-')
CONFIG = json.loads((ROOT / 'Config/Release.json').read_text())
VERSION = CONFIG['version']

def run(*args):
    print('+', ' '.join(map(str, args)), flush=True)
    subprocess.run(list(map(str, args)), cwd=ROOT, check=True)

def sign(path, helper=False):
    args = ['codesign', '--force', '--sign', IDENTITY]
    if IDENTITY != '-':
        args += ['--options', 'runtime', '--timestamp']
        if helper: args += ['--entitlements', ROOT / 'scripts/helper-entitlements.plist']
    run(*args, path)

def main():
    DIST.mkdir(exist_ok=True)
    BUILD.mkdir(parents=True, exist_ok=True)
    sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
    sources = sorted((ROOT / 'Sources/Resonance').glob('*.swift'))
    sparkle = ROOT / 'vendor/sparkle'
    if not (sparkle / 'Sparkle.framework').exists(): raise SystemExit('Run scripts/fetch-vendor.py first.')
    for arch in ['arm64', 'x86_64']:
        binary = BUILD / f'Resonance-{arch}'
        if '--package-only' in sys.argv:
            if not binary.exists() or any(s.stat().st_mtime > binary.stat().st_mtime for s in sources):
                raise SystemExit('Sources changed: run the full build.')
        else:
            run('swiftc', '-parse-as-library', '-O', '-whole-module-optimization', '-swift-version', '5',
                '-target', f'{arch}-apple-macosx{CONFIG["minimum_macos"]}', '-sdk', sdk,
                '-F', sparkle, '-framework', 'Sparkle', '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks',
                '-module-name', 'Resonance', *sources, '-o', binary)
    # Recreate only generated outputs, preventing removed components from surviving rebuilds.
    if APP.exists(): shutil.rmtree(APP)
    (APP / 'Contents/MacOS').mkdir(parents=True)
    RESOURCES.mkdir(parents=True)
    run('lipo', '-create', *(BUILD / f'Resonance-{a}' for a in ['arm64', 'x86_64']), '-output', APP / 'Contents/MacOS/Resonance')
    tools = RESOURCES / 'Tools'
    tools.mkdir()
    shutil.copy2(ROOT / 'vendor/bin/arm64/yt-dlp', tools / 'yt-dlp')
    sign(tools / 'yt-dlp', helper=True)
    for arch in ['arm64', 'x86_64']:
        target = tools / arch
        target.mkdir()
        for name in ['ffmpeg', 'ffprobe', 'qjs']:
            shutil.copy2(ROOT / 'vendor/bin' / arch / name, target / name)
            (target / name).chmod(0o755)
            sign(target / name, helper=True)
        (target / 'yt-dlp').symlink_to('../yt-dlp')
    framework = APP / 'Contents/Frameworks/Sparkle.framework'
    framework.parent.mkdir()
    shutil.copytree(sparkle / 'Sparkle.framework', framework, symlinks=True)
    base = framework / 'Versions/B'
    sign(base / 'Autoupdate')
    for nested in sorted([*base.rglob('*.xpc'), *base.rglob('*.app')], key=lambda p: len(p.parts), reverse=True): sign(nested)
    sign(framework)
    iconset = BUILD / 'AppIcon.iconset'
    run('swift', ROOT / 'scripts/make-icon.swift', iconset)
    run('iconutil', '-c', 'icns', iconset, '-o', RESOURCES / 'AppIcon.icns')
    repo = os.environ.get('RESONANCE_REPOSITORY', CONFIG['repository'])
    public_key = (ROOT / 'Config/UpdatePublicKey.txt').read_text().strip()
    info = {
        'CFBundleDevelopmentRegion': 'en', 'CFBundleLocalizations': ['en', 'it'],
        'CFBundleExecutable': 'Resonance', 'CFBundleIdentifier': CONFIG['bundle_id'],
        'CFBundleName': 'Resonance', 'CFBundleDisplayName': 'Resonance', 'CFBundlePackageType': 'APPL',
        'CFBundleShortVersionString': VERSION, 'CFBundleVersion': CONFIG['build'],
        'CFBundleIconFile': 'AppIcon', 'LSMinimumSystemVersion': CONFIG['minimum_macos'],
        'NSHighResolutionCapable': True, 'NSHumanReadableCopyright': 'Copyright © 2026 Resonance contributors. GPL-3.0-or-later.',
        'ResonanceRepositoryURL': f'https://github.com/{repo}',
        'SUFeedURL': f'https://github.com/{repo}/releases/latest/download/appcast.xml',
        'SUPublicEDKey': public_key, 'SUEnableAutomaticChecks': True,
        'SUScheduledCheckInterval': 86400, 'SUAutomaticallyUpdate': False,
        'SUAllowsAutomaticUpdates': False, 'SUEnableSystemProfiling': False,
        'SUVerifyUpdateBeforeExtraction': True,
        'SURequireSignedFeed': True,
    }
    (APP / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    for lang in ['en', 'it']:
        shutil.copytree(ROOT / f'Sources/Resonance/Resources/{lang}.lproj', RESOURCES / f'{lang}.lproj')
    shutil.copytree(ROOT / 'vendor/licenses', RESOURCES / 'Licenses')
    (RESOURCES / 'Licenses/Dependencies.json').write_text(json.dumps(Manifest().resolved(), indent=2) + '\n')
    shutil.copy2(sparkle / 'LICENSE', RESOURCES / 'Licenses/Sparkle.txt')
    shutil.copy2(ROOT / 'LICENSE', RESOURCES / 'Licenses/Resonance-GPLv3.txt')
    shutil.copy2(ROOT / 'README.md', RESOURCES / 'Guide.md')
    sign(APP)
    run('codesign', '--verify', '--deep', '--strict', APP)
    profile = os.environ.get('RESONANCE_NOTARY_PROFILE')
    if profile:
        archive = BUILD / 'notarization.zip'
        run('ditto', '-c', '-k', '--keepParent', APP, archive)
        run('xcrun', 'notarytool', 'submit', archive, '--keychain-profile', profile, '--wait')
        run('xcrun', 'stapler', 'staple', APP)
    local_app = DIST / 'Resonance.app'
    if local_app.exists(): shutil.rmtree(local_app)
    run('ditto', APP, local_app)
    zip_file = DIST / f'Resonance-{VERSION}-universal.zip'
    run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', APP, zip_file)
    component = BUILD / 'Resonance-component.pkg'
    run('pkgbuild', '--root', BUILD / 'root', '--identifier', CONFIG['bundle_id'], '--version', VERSION,
        '--install-location', '/', '--ownership', 'recommended', component)
    distribution = BUILD / 'Distribution.xml'
    distribution.write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>Resonance</title>
  <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
  <domains enable_localSystem="true" enable_currentUserHome="false" enable_anywhere="false"/>
  <allowed-os-versions><os-version min="{CONFIG['minimum_macos']}"/></allowed-os-versions>
  <choices-outline><line choice="default"/></choices-outline>
  <choice id="default" title="Resonance" visible="false"><pkg-ref id="{CONFIG['bundle_id']}"/></choice>
  <pkg-ref id="{CONFIG['bundle_id']}" version="{VERSION}">Resonance-component.pkg</pkg-ref>
</installer-gui-script>
''')
    package = DIST / f'Resonance-{VERSION}-universal.pkg'
    installer_identity = os.environ.get('RESONANCE_INSTALLER_IDENTITY')
    args = ['productbuild', '--distribution', distribution, '--package-path', BUILD]
    if installer_identity: args += ['--sign', installer_identity]
    run(*args, package)
    if profile:
        run('xcrun', 'notarytool', 'submit', package, '--keychain-profile', profile, '--wait')
        run('xcrun', 'stapler', 'staple', package)
    hashes = {path.name: hashlib.file_digest(path.open('rb'), 'sha256').hexdigest() for path in [package, zip_file]}
    (DIST / 'SHA256SUMS.txt').write_text(''.join(f'{digest}  {name}\n' for name, digest in hashes.items()))
    print('Build ready:', package, flush=True)

if __name__ == '__main__': main()
