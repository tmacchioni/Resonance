#!/usr/bin/env python3
"""Fail early with actionable diagnostics when a tag points to inconsistent metadata."""
import json
import os
from pathlib import Path
from release_config import validate_release

root = Path(__file__).resolve().parent.parent
config = json.loads((root / 'Config/Release.json').read_text())
try:
    validate_release(config, os.environ.get('RELEASE_TAG', ''), os.environ.get('RELEASE_REPOSITORY', ''))
except ValueError as error:
    raise SystemExit(str(error))
print(f'Release validated: {config["version"]}, build {config["build"]}')
