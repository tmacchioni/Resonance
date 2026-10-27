import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'scripts'))
from release_config import validate_release

class ReleaseConfigTests(unittest.TestCase):
    def setUp(self):
        self.config = {'version': '1.1.2', 'build': '112', 'repository': 'owner/repo'}

    def test_matching_release(self):
        validate_release(self.config, 'v1.1.2', 'owner/repo')

    def test_mismatch_names_both_versions_and_explains_recovery(self):
        with self.assertRaises(ValueError) as caught:
            validate_release(self.config, 'v1.1.1', 'owner/repo')
        for text in ['v1.1.1', 'v1.1.2', 'Config/Release.json', 'commit', 'Re-running']:
            self.assertIn(text, str(caught.exception))

    def test_invalid_build_and_wrong_repository(self):
        with self.assertRaises(ValueError): validate_release(self.config, 'v1.1.2', 'wrong/repo')
        for build in ['0', '112a', 112, None]:
            with self.subTest(build=build), self.assertRaises(ValueError):
                validate_release(dict(self.config, build=build), 'v1.1.2', 'owner/repo')

if __name__ == '__main__': unittest.main()
