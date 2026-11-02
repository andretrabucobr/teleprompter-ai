#!/usr/bin/env python3
"""Aplica a abertura com fundo preto e a logo Oitosete após flutter create.

Idempotente. Executado pela etapa de configuração de plataformas do workflow.
A tela Flutter com a mesma logo continua visível por 1,5 s.
"""
from __future__ import annotations

from pathlib import Path
import argparse
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / 'scripts' / 'launch_assets'
ANDROID = ROOT / 'android' / 'app' / 'src' / 'main'
IOS = ROOT / 'ios' / 'Runner'

# Bitmap leve (250px) centrado sobre fundo preto antes do primeiro frame.
LAUNCH_XML = '''<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@android:color/black" />
    <item>
        <bitmap android:gravity="center" android:src="@drawable/otst_logo" />
    </item>
</layer-list>
'''


def android():
    if not ANDROID.is_dir():
        raise SystemExit('Android não gerado. Execute flutter create --platforms=android .')
    folder = ANDROID / 'res' / 'drawable-nodpi'
    folder.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(NATIVE / 'otst_logo_250.png', folder / 'otst_logo.png')
    for name in ('drawable', 'drawable-v21'):
        drawable = ANDROID / 'res' / name / 'launch_background.xml'
        drawable.parent.mkdir(parents=True, exist_ok=True)
        drawable.write_text(LAUNCH_XML, encoding='utf-8')
    styles = ANDROID / 'res' / 'values' / 'styles.xml'
    if styles.exists():
        content = styles.read_text(encoding='utf-8')
        # Mantém o launch_background do Flutter; troca o plano de fundo normal.
        content = content.replace('?android:colorBackground', '@android:color/black')
        styles.write_text(content, encoding='utf-8')
    for styles in (ANDROID / 'res' / 'values-v31' / 'styles.xml',
                   ANDROID / 'res' / 'values-night-v31' / 'styles.xml'):
        if styles.exists():
            content = styles.read_text(encoding='utf-8')
            content = re.sub(r'(<item name="android:windowSplashScreenBackground">).*?(</item>)',
                             r'\g<1>@android:color/black\g<2>', content)
            styles.write_text(content, encoding='utf-8')
    print('Splash Android: fundo preto e logo configurados.')


def ios():
    if not IOS.is_dir():
        raise SystemExit('iOS não gerado. Execute flutter create --platforms=ios .')
    folder = IOS / 'Assets.xcassets' / 'LaunchImage.imageset'
    folder.mkdir(parents=True, exist_ok=True)
    for name, size in (('LaunchImage.png', 250),
                       ('LaunchImage@2x.png', 500),
                       ('LaunchImage@3x.png', 750)):
        shutil.copyfile(NATIVE / f'otst_logo_{size}.png', folder / name)
    storyboard = IOS / 'Base.lproj' / 'LaunchScreen.storyboard'
    if storyboard.exists():
        content = storyboard.read_text(encoding='utf-8')
        background = ('<color key="backgroundColor" red="0.0" green="0.0" '
                      'blue="0.0" alpha="1" colorSpace="custom" '
                      'customColorSpace="sRGB"/>')
        content, count = re.subn(r'<color\s+key="backgroundColor"[^>]*/>',
                                 background, content)
        if count == 0:
            raise SystemExit('Cor de fundo do storyboard iOS não encontrada; '
                             'verifique o LaunchScreen.storyboard.')
        storyboard.write_text(content, encoding='utf-8')
    print('Splash iOS: fundo preto e logo configurados.')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--platform', choices=['android', 'ios', 'both'], required=True)
    args = parser.parse_args()
    if args.platform in ('android', 'both'):
        android()
    if args.platform in ('ios', 'both'):
        ios()

if __name__ == '__main__':
    main()
