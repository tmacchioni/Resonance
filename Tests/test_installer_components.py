import copy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'scripts'))
from installer_components import pin_components

class InstallerComponentTests(unittest.TestCase):
    def test_disables_relocation_for_app_and_nested_framework_helpers(self):
        analyzed = [{'RootRelativeBundlePath': 'Applications/Resonance.app', 'BundleIsRelocatable': True,
                     'ChildBundles': [{'RootRelativeBundlePath': 'Applications/Resonance.app/Contents/Frameworks/Sparkle.framework',
                                       'ChildBundles': [{'RootRelativeBundlePath': 'Updater.app'}]}]}]
        pinned = pin_components(copy.deepcopy(analyzed))[0]
        self.assertIs(pinned['BundleIsRelocatable'], False)
        framework = pinned['ChildBundles'][0]
        self.assertIs(framework['BundleIsRelocatable'], False)
        self.assertIs(framework['ChildBundles'][0]['BundleIsRelocatable'], False)
        self.assertEqual(pinned['RootRelativeBundlePath'], 'Applications/Resonance.app')

    def test_rejects_wrong_installation_path_and_multiple_apps(self):
        for analyzed in [[], [{'RootRelativeBundlePath': 'Other/Resonance.app'}], [{}, {}]]:
            with self.subTest(analyzed=analyzed), self.assertRaises(ValueError): pin_components(analyzed)

if __name__ == '__main__': unittest.main()
