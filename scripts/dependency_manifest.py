#!/usr/bin/env python3
"""Single dependency catalog shared by fetch, build, validation and release tools."""
from dataclasses import asdict, dataclass
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import tarfile
import tempfile
from string import Formatter
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent.parent
REQUIRED = {'yt-dlp', 'sparkle', 'ffmpeg', 'lame', 'opus', 'quickjs-ng'}
SOURCE_COMPONENTS = ('ffmpeg', 'lame', 'opus', 'quickjs-ng')

def file_sha256(path):
    with Path(path).open('rb') as source: return hashlib.file_digest(source, 'sha256').hexdigest()

@dataclass(frozen=True)
class Dependency:
    component: str
    version: str
    file: str
    url: str
    sha256: str
    source_directory: str | None = None

def relative_path(value, label):
    if not isinstance(value, str) or not value or '\\' in value or '\x00' in value:
        raise ValueError(f'Invalid {label}')
    path = PurePosixPath(value)
    if path.is_absolute() or any(part in ('.', '..') for part in value.split('/')):
        raise ValueError(f'Unsafe {label}: {value}')
    return value

class Manifest:
    def __init__(self, root=ROOT, path=None):
        self.root = Path(root)
        self.raw = json.loads(Path(path or self.root / 'vendor/manifest.json').read_text())
        if self.raw.get('schema_version') != 1: raise ValueError('Unsupported dependency manifest schema')
        versions = self.raw.get('versions', {})
        if set(versions) != REQUIRED: raise ValueError('Manifest must declare exactly the supported components')
        self.dependencies = {}
        filenames = set()
        for item in self.raw.get('assets', []):
            name = item.get('component')
            if name not in REQUIRED or name in self.dependencies: raise ValueError(f'Unknown or repeated component: {name}')
            version = versions[name]
            if not isinstance(version, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._+-]*', version):
                raise ValueError(f'Invalid version for {name}')
            def expand(value):
                try:
                    if any(field is not None and (field != 'version' or spec or conversion) for _, field, spec, conversion in Formatter().parse(value)):
                        raise ValueError('Only {version} placeholders are supported')
                    return value.format(version=version)
                except (KeyError, ValueError, AttributeError) as error: raise ValueError(f'Invalid template for {name}') from error
            filename = relative_path(expand(item.get('file')), 'asset filename')
            if '/' in filename or filename in filenames: raise ValueError(f'Asset filename must be unique and flat: {filename}')
            filenames.add(filename)
            url = expand(item.get('url'))
            parsed = urlsplit(url)
            if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password:
                raise ValueError(f'Expected a public HTTPS asset URL for {name}')
            digest = item.get('sha256', '')
            if not isinstance(digest, str) or not re.fullmatch(r'[a-f0-9]{64}', digest): raise ValueError(f'Invalid SHA-256 for {name}')
            directory = item.get('source_directory')
            if name in SOURCE_COMPONENTS and directory is None: raise ValueError(f'Missing source directory for {name}')
            if directory is not None: directory = relative_path(expand(directory), 'source directory')
            self.dependencies[name] = Dependency(name, version, filename, url, digest, directory)
        if set(self.dependencies) != REQUIRED: raise ValueError('Each component needs exactly one asset')

    def get(self, name): return self.dependencies[name]

    def cache_path(self, name):
        dependency = self.get(name)
        return self.root / 'vendor/cache' / dependency.sha256 / dependency.file

    def verified_archive(self, name):
        dependency = self.get(name)
        path = self.cache_path(name)
        if not path.is_file(): raise ValueError(f'Missing {name} archive; run python3 scripts/fetch-vendor.py')
        if file_sha256(path) != dependency.sha256:
            raise ValueError(f'Checksum mismatch for {name}; the cached file was not installed')
        return path

    def extract_source(self, name):
        dependency = self.get(name)
        archive_path = self.verified_archive(name)
        if not dependency.source_directory: raise ValueError(f'{name} is not a source archive')
        parent = self.root / 'vendor/sources' / name / dependency.sha256
        source = parent / dependency.source_directory
        marker = parent / '.verified'
        if source.is_dir() and marker.is_file() and marker.read_text() == dependency.sha256: return source
        parent.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=parent.parent) as temporary:
            staging = Path(temporary) / 'source'
            staging.mkdir()
            with tarfile.open(archive_path) as archive: archive.extractall(staging, filter='data')
            if not (staging / dependency.source_directory).is_dir():
                raise ValueError(f'The {name} archive does not contain {dependency.source_directory}')
            (staging / '.verified').write_text(dependency.sha256)
            if parent.exists(): shutil.rmtree(parent)
            staging.rename(parent)
        return source

    def fingerprint(self, names, recipe):
        data = json.dumps([asdict(self.get(name)) for name in names], sort_keys=True).encode()
        return hashlib.sha256(data + recipe).hexdigest()[:16]

    def resolved(self): return {name: asdict(value) for name, value in self.dependencies.items()}

if __name__ == '__main__':
    manifest = Manifest()
    for name, dependency in manifest.dependencies.items(): print(f'{name}: {dependency.version} ({dependency.file})')
