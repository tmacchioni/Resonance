"""Dependency updates must change every consumer and invalidate stale build inputs."""
import copy
import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'scripts'))
from dependency_manifest import Manifest

class DependencyManifestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'vendor').mkdir()
        self.raw = json.loads((ROOT / 'vendor/manifest.json').read_text())

    def load(self, raw=None):
        (self.root / 'vendor/manifest.json').write_text(json.dumps(self.raw if raw is None else raw))
        return Manifest(self.root)

    def test_version_change_updates_url_filename_directory_and_build_cache(self):
        original = self.load()
        self.raw['versions']['ffmpeg'] = '99.1.2'
        updated = self.load()
        self.assertEqual(updated.get('ffmpeg').file, 'ffmpeg-99.1.2.tar.xz')
        self.assertEqual(updated.get('ffmpeg').source_directory, 'ffmpeg-99.1.2')
        self.assertIn('/ffmpeg-99.1.2.tar.xz', updated.get('ffmpeg').url)
        self.assertNotEqual(original.fingerprint(['ffmpeg'], b'recipe'), updated.fingerprint(['ffmpeg'], b'recipe'))
        self.assertEqual(original.fingerprint(['quickjs-ng'], b'recipe'), updated.fingerprint(['quickjs-ng'], b'recipe'))

    def test_hash_change_isolated_even_when_asset_filename_is_unchanged(self):
        original = self.load()
        next(a for a in self.raw['assets'] if a['component'] == 'yt-dlp')['sha256'] = 'a' * 64
        updated = self.load()
        self.assertEqual(original.get('yt-dlp').file, updated.get('yt-dlp').file)
        self.assertNotEqual(original.cache_path('yt-dlp'), updated.cache_path('yt-dlp'))

    def test_invalid_manifests_are_rejected_before_any_download(self):
        cases = []
        for field, value in [('file', '../escape'), ('url', 'http://example.com/file'),
                             ('url', 'https://user:password@example.com/file'), ('sha256', 'wrong'),
                             ('file', '{unknown}.tar.gz'), ('source_directory', '/outside')]:
            raw = copy.deepcopy(self.raw)
            asset = next(a for a in raw['assets'] if a['component'] == 'ffmpeg')
            asset[field] = value
            cases.append(raw)
        repeated = copy.deepcopy(self.raw)
        repeated['assets'].append(repeated['assets'][0])
        cases.append(repeated)
        missing = copy.deepcopy(self.raw)
        missing['assets'].pop()
        cases.append(missing)
        for raw in cases:
            with self.subTest(raw=raw), self.assertRaises(ValueError): self.load(raw)

    def test_tampered_cache_is_rejected(self):
        manifest = self.load()
        cache = manifest.cache_path('yt-dlp')
        cache.parent.mkdir(parents=True)
        cache.write_bytes(b'wrong executable')
        with self.assertRaisesRegex(ValueError, 'Checksum mismatch'): manifest.verified_archive('yt-dlp')

    def test_extracts_exact_source_and_rejects_missing_expected_directory(self):
        payload = io.BytesIO()
        with tarfile.open(fileobj=payload, mode='w:gz') as archive:
            entry = tarfile.TarInfo('ffmpeg-test/README')
            entry.size = 4
            archive.addfile(entry, io.BytesIO(b'test'))
        asset = next(a for a in self.raw['assets'] if a['component'] == 'ffmpeg')
        asset['sha256'] = hashlib.sha256(payload.getvalue()).hexdigest()
        asset['source_directory'] = 'ffmpeg-test'
        manifest = self.load()
        cache = manifest.cache_path('ffmpeg')
        cache.parent.mkdir(parents=True)
        cache.write_bytes(payload.getvalue())
        source = manifest.extract_source('ffmpeg')
        self.assertEqual((source / 'README').read_text(), 'test')
        self.assertEqual(source, manifest.extract_source('ffmpeg'))
        asset['source_directory'] = 'missing'
        manifest = self.load()
        with self.assertRaisesRegex(ValueError, 'does not contain'): manifest.extract_source('ffmpeg')

if __name__ == '__main__': unittest.main()
