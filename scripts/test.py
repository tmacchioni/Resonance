#!/usr/bin/env python3
"""Run engine tests with Command Line Tools; a full Xcode install is unnecessary."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent.parent
output = root / '.build/checks'
output.parent.mkdir(exist_ok=True)
subprocess.run(['swiftc', '-parse-as-library', '-O', '-swift-version', '5',
                str(root / 'Sources/Resonance/Localization.swift'),
                str(root / 'Sources/Resonance/Models.swift'),
                str(root / 'Sources/Resonance/Engine.swift'),
                str(root / 'Tests/ResonanceTests/ResonanceTests.swift'), '-o', str(output)], cwd=root, check=True)
subprocess.run([str(output)], cwd=root, check=True)
