#!/usr/bin/env python3
"""Optional Developer ID import for ephemeral GitHub runners. Never prints secrets."""
import base64
import os
from pathlib import Path
import secrets
import subprocess
import sys

temp = Path(os.environ['RUNNER_TEMP'])
keychain = temp / 'resonance-signing.keychain-db'
certificate = temp / 'resonance-signing.p12'

def run(*args): subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

if '--cleanup' in sys.argv:
    certificate.unlink(missing_ok=True)
    if keychain.exists(): run('security', 'delete-keychain', str(keychain))
    sys.exit(0)

encoded = os.environ.get('APPLE_CERTIFICATES_BASE64')
if not encoded:
    print('No Developer ID credentials configured: producing an ad-hoc signed release (not notarized).')
    sys.exit(0)
password = secrets.token_urlsafe(32)
certificate.write_bytes(base64.b64decode(encoded))
certificate.chmod(0o600)
run('security', 'create-keychain', '-p', password, str(keychain))
run('security', 'set-keychain-settings', '-lut', '21600', str(keychain))
run('security', 'unlock-keychain', '-p', password, str(keychain))
run('security', 'import', str(certificate), '-P', os.environ['APPLE_CERTIFICATE_PASSWORD'], '-A', '-t', 'cert', '-f', 'pkcs12', '-k', str(keychain))
run('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:', '-k', password, str(keychain))
run('security', 'list-keychains', '-d', 'user', '-s', str(keychain))
certificate.unlink()
values = {'RESONANCE_SIGN_IDENTITY': os.environ['APPLE_SIGN_IDENTITY'],
          'RESONANCE_INSTALLER_IDENTITY': os.environ['APPLE_INSTALLER_IDENTITY']}
if all(os.environ.get(name) for name in ['APPLE_ID', 'APPLE_TEAM_ID', 'APPLE_APP_PASSWORD']):
    run('xcrun', 'notarytool', 'store-credentials', 'resonance-ci', '--keychain', str(keychain),
        '--apple-id', os.environ['APPLE_ID'], '--team-id', os.environ['APPLE_TEAM_ID'], '--password', os.environ['APPLE_APP_PASSWORD'])
    values['RESONANCE_NOTARY_PROFILE'] = 'resonance-ci'
with open(os.environ['GITHUB_ENV'], 'a') as output:
    for key, value in values.items():
        if '\n' in value or '\r' in value: raise SystemExit('Invalid signing configuration')
        output.write(f'{key}={value}\n')
print('Developer ID signing configured in a temporary keychain.')
