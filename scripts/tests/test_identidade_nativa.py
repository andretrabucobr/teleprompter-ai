"""Smoke tests for installed display names, icons, and launch screens."""
import json
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]


class IdentidadeNativaTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'scripts').mkdir()
        for name in ('configurar_plataformas.py', 'configurar_splash.py'):
            shutil.copy2(PROJECT / 'scripts' / name, self.root / 'scripts' / name)
        shutil.copytree(PROJECT / 'scripts/icon_assets', self.root / 'scripts/icon_assets')
        shutil.copytree(PROJECT / 'scripts/launch_assets', self.root / 'scripts/launch_assets')

    def configure(self, platform):
        for script in ('configurar_plataformas.py', 'configurar_splash.py'):
            subprocess.run(
                [sys.executable, str(self.root / 'scripts' / script), '--platform', platform],
                cwd=self.root, check=True, capture_output=True, text=True,
            )

    def test_android_name_icon_and_splash_are_idempotent(self):
        main = self.root / 'android/app/src/main'
        main.mkdir(parents=True)
        (main / 'AndroidManifest.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="teleprompter_ai" android:icon="@mipmap/ic_launcher">
        <activity android:name=".MainActivity" />
    </application>
</manifest>
''', encoding='utf-8')
        gradle = self.root / 'android/app/build.gradle.kts'
        gradle.write_text('android { defaultConfig { minSdk = flutter.minSdkVersion } }', encoding='utf-8')
        styles = main / 'res/values/styles.xml'
        styles.parent.mkdir(parents=True, exist_ok=True)
        styles.write_text('<resources><style name="NormalTheme"><item name="android:windowBackground">?android:colorBackground</item></style></resources>')

        self.configure('android')
        first = (main / 'AndroidManifest.xml').read_text()
        self.configure('android')
        self.assertEqual((main / 'AndroidManifest.xml').read_text(), first)
        android_label = '{http://schemas.android.com/apk/res/android}label'
        app = ET.parse(main / 'AndroidManifest.xml').getroot().find('application')
        self.assertEqual(app.attrib[android_label], 'Oitosete FlowText')
        self.assertIn('minSdk = 24', gradle.read_text())
        self.assertTrue((main / 'res/mipmap-hdpi/ic_launcher.png').is_file())
        self.assertTrue((main / 'res/mipmap-anydpi-v26/ic_launcher.xml').is_file())
        self.assertTrue((main / 'res/drawable-nodpi/otst_logo.png').is_file())
        self.assertIn('@android:color/black', (main / 'res/drawable/launch_background.xml').read_text())

    def test_ios_display_name_icon_and_splash_are_idempotent(self):
        runner = self.root / 'ios/Runner'
        (runner / 'Base.lproj').mkdir(parents=True)
        with (runner / 'Info.plist').open('wb') as out:
            plistlib.dump({'CFBundleDisplayName': 'teleprompter_ai', 'CFBundleName': 'Runner'}, out)
        (runner / 'Base.lproj/LaunchScreen.storyboard').write_text(
            '<document><color key="backgroundColor" red="1" green="1" blue="1" alpha="1"/></document>',
            encoding='utf-8',
        )
        self.configure('ios')
        with (runner / 'Info.plist').open('rb') as f:
            first = plistlib.load(f)
        self.configure('ios')
        with (runner / 'Info.plist').open('rb') as f:
            second = plistlib.load(f)
        self.assertEqual(first, second)
        self.assertEqual(second['CFBundleDisplayName'], 'Oitosete FlowText')
        self.assertEqual(second['CFBundleName'], 'OitoseteFlow')
        appicon = runner / 'Assets.xcassets/AppIcon.appiconset'
        manifest = json.loads((appicon / 'Contents.json').read_text())
        self.assertEqual(len(manifest['images']), 18)
        for icon in manifest['images']:
            self.assertTrue((appicon / icon['filename']).is_file(), icon)
        self.assertTrue((runner / 'Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png').is_file())
        self.assertIn('red="0.0"', (runner / 'Base.lproj/LaunchScreen.storyboard').read_text())


if __name__ == '__main__':
    unittest.main()
