#!/usr/bin/env python3
"""Configura permissões nativas e aplica o ícone do app após `flutter create`.

Idempotente. Funciona mesmo quando apenas Android ou apenas iOS estiverem
presentes no projeto gerado.
"""
from pathlib import Path
import argparse
import json
import plistlib
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
ANDROID_MANIFEST = ROOT / 'android/app/src/main/AndroidManifest.xml'
IOS_INFO = ROOT / 'ios/Runner/Info.plist'
ICON_ASSETS = ROOT / 'scripts' / 'icon_assets'
APP_DISPLAY_NAME = 'Oitosete FlowText'


def _copy(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)


def configurar_icone_android() -> None:
    base = ROOT / 'android' / 'app' / 'src' / 'main' / 'res'
    assets = ICON_ASSETS / 'android'
    if not base.is_dir() or not assets.is_dir():
        raise SystemExit('Android: os arquivos scripts/icon_assets/android são necessários para o ícone.')

    legacy = {
        'mipmap-mdpi': 'ic_launcher_mdpi.png',
        'mipmap-hdpi': 'ic_launcher_hdpi.png',
        'mipmap-xhdpi': 'ic_launcher_xhdpi.png',
        'mipmap-xxhdpi': 'ic_launcher_xxhdpi.png',
        'mipmap-xxxhdpi': 'ic_launcher_xxxhdpi.png',
    }
    for folder, filename in legacy.items():
        _copy(assets / filename, base / folder / 'ic_launcher.png')
        _copy(assets / filename, base / folder / 'ic_launcher_round.png')

    _copy(assets / 'ic_launcher_foreground.png', base / 'drawable' / 'ic_launcher_foreground.png')

    colors = base / 'values' / 'colors.xml'
    colors.parent.mkdir(parents=True, exist_ok=True)
    color_text = colors.read_text(encoding='utf-8') if colors.exists() else '<resources>\n</resources>\n'
    if 'ic_launcher_background' in color_text:
        color_text = re.sub(
            r'<color name="ic_launcher_background">.*?</color>',
            '<color name="ic_launcher_background">#000000</color>',
            color_text,
            flags=re.S,
        )
    else:
        color_text = color_text.replace(
            '</resources>',
            '    <color name="ic_launcher_background">#000000</color>\n</resources>'
        )
    colors.write_text(color_text, encoding='utf-8')

    anydpi = base / 'mipmap-anydpi-v26'
    anydpi.mkdir(parents=True, exist_ok=True)
    adaptive = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
'''
    (anydpi / 'ic_launcher.xml').write_text(adaptive, encoding='utf-8')
    (anydpi / 'ic_launcher_round.xml').write_text(adaptive, encoding='utf-8')
    print('Android: ícone configurado (fundo preto com a logo).')


def configurar_icone_ios() -> None:
    assets = ICON_ASSETS / 'ios'
    appicon = ROOT / 'ios' / 'Runner' / 'Assets.xcassets' / 'AppIcon.appiconset'
    if not (ROOT / 'ios' / 'Runner').is_dir() or not assets.is_dir():
        raise SystemExit('iOS: os arquivos scripts/icon_assets/ios são necessários para o ícone.')

    appicon.mkdir(parents=True, exist_ok=True)
    names = [
        'Icon-App-20x20@1x.png', 'Icon-App-20x20@2x.png', 'Icon-App-20x20@3x.png',
        'Icon-App-29x29@1x.png', 'Icon-App-29x29@2x.png', 'Icon-App-29x29@3x.png',
        'Icon-App-40x40@1x.png', 'Icon-App-40x40@2x.png', 'Icon-App-40x40@3x.png',
        'Icon-App-60x60@2x.png', 'Icon-App-60x60@3x.png',
        'Icon-App-76x76@1x.png', 'Icon-App-76x76@2x.png',
        'Icon-App-83.5x83.5@2x.png', 'Icon-App-1024x1024@1x.png',
    ]
    for name in names:
        _copy(assets / name, appicon / name)

    contents = {
        'images': [
            {'size': '20x20', 'idiom': 'iphone', 'filename': 'Icon-App-20x20@2x.png', 'scale': '2x'},
            {'size': '20x20', 'idiom': 'iphone', 'filename': 'Icon-App-20x20@3x.png', 'scale': '3x'},
            {'size': '29x29', 'idiom': 'iphone', 'filename': 'Icon-App-29x29@2x.png', 'scale': '2x'},
            {'size': '29x29', 'idiom': 'iphone', 'filename': 'Icon-App-29x29@3x.png', 'scale': '3x'},
            {'size': '40x40', 'idiom': 'iphone', 'filename': 'Icon-App-40x40@2x.png', 'scale': '2x'},
            {'size': '40x40', 'idiom': 'iphone', 'filename': 'Icon-App-40x40@3x.png', 'scale': '3x'},
            {'size': '60x60', 'idiom': 'iphone', 'filename': 'Icon-App-60x60@2x.png', 'scale': '2x'},
            {'size': '60x60', 'idiom': 'iphone', 'filename': 'Icon-App-60x60@3x.png', 'scale': '3x'},
            {'size': '20x20', 'idiom': 'ipad', 'filename': 'Icon-App-20x20@1x.png', 'scale': '1x'},
            {'size': '20x20', 'idiom': 'ipad', 'filename': 'Icon-App-20x20@2x.png', 'scale': '2x'},
            {'size': '29x29', 'idiom': 'ipad', 'filename': 'Icon-App-29x29@1x.png', 'scale': '1x'},
            {'size': '29x29', 'idiom': 'ipad', 'filename': 'Icon-App-29x29@2x.png', 'scale': '2x'},
            {'size': '40x40', 'idiom': 'ipad', 'filename': 'Icon-App-40x40@1x.png', 'scale': '1x'},
            {'size': '40x40', 'idiom': 'ipad', 'filename': 'Icon-App-40x40@2x.png', 'scale': '2x'},
            {'size': '76x76', 'idiom': 'ipad', 'filename': 'Icon-App-76x76@1x.png', 'scale': '1x'},
            {'size': '76x76', 'idiom': 'ipad', 'filename': 'Icon-App-76x76@2x.png', 'scale': '2x'},
            {'size': '83.5x83.5', 'idiom': 'ipad', 'filename': 'Icon-App-83.5x83.5@2x.png', 'scale': '2x'},
            {'size': '1024x1024', 'idiom': 'ios-marketing', 'filename': 'Icon-App-1024x1024@1x.png', 'scale': '1x'},
        ],
        'info': {'version': 1, 'author': 'xcode'},
    }
    (appicon / 'Contents.json').write_text(
        json.dumps(contents, indent=2, ensure_ascii=False) + '\n',
        encoding='utf-8'
    )
    print('iOS: ícone configurado (fundo preto com a logo).')


def configurar_android() -> None:
    if not ANDROID_MANIFEST.is_file():
        raise SystemExit('Android não encontrado. Execute: flutter create --platforms=android .')
    content = ANDROID_MANIFEST.read_text(encoding='utf-8')
    for permission in (
        'android.permission.INTERNET',
        'android.permission.CAMERA',
        'android.permission.RECORD_AUDIO',
        'android.permission.ACCESS_NETWORK_STATE',
        'android.permission.ACCESS_WIFI_STATE',
    ):
        if f'android:name="{permission}"' not in content:
            content = content.replace(
                '<application',
                f'<uses-permission android:name="{permission}" />\n    <application',
                1,
            )
    if 'android.speech.RecognitionService' not in content:
        query = (
            '<queries>\n        <intent>\n'
            '            <action android:name="android.speech.RecognitionService" />\n'
            '        </intent>\n    </queries>\n    '
        )
        content = content.replace('<application', query + '<application', 1)
    if 'android:usesCleartextTraffic=' not in content:
        content = content.replace('<application', '<application android:usesCleartextTraffic="true"', 1)
    # O nome visível no launcher e na instalação não é o nome interno do pacote.
    label_pattern = r'(<application\b[^>]*\bandroid:label\s*=\s*")[^"]*(")'
    content, count = re.subn(
        label_pattern, lambda match: match.group(1) + APP_DISPLAY_NAME + match.group(2),
        content, count=1, flags=re.S,
    )
    if count == 0:
        if '<application' not in content:
            raise SystemExit('AndroidManifest.xml sem tag <application>.')
        content = content.replace('<application',
                                  f'<application android:label="{APP_DISPLAY_NAME}"', 1)
    ANDROID_MANIFEST.write_text(content, encoding='utf-8')

    for gradle in (ROOT / 'android/app/build.gradle.kts', ROOT / 'android/app/build.gradle'):
        if gradle.is_file():
            value = gradle.read_text(encoding='utf-8')
            value = value.replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')
            value = value.replace('minSdkVersion flutter.minSdkVersion', 'minSdkVersion 24')
            gradle.write_text(value, encoding='utf-8')
            break
    configurar_icone_android()
    print('Android: permissões e SDK mínimo configurados (API 24).')


def configurar_ios() -> None:
    if not IOS_INFO.is_file():
        raise SystemExit('iOS não encontrado. No macOS, execute: flutter create --platforms=ios .')
    with IOS_INFO.open('rb') as f:
        plist = plistlib.load(f)
    plist['CFBundleDisplayName'] = APP_DISPLAY_NAME
    plist['CFBundleName'] = 'OitoseteFlow'
    plist['NSCameraUsageDescription'] = 'A câmera permite gravar vídeos usando o teleprompter.'
    plist['NSMicrophoneUsageDescription'] = 'O microfone é usado para gravar vídeos e acompanhar a fala.'
    plist['NSSpeechRecognitionUsageDescription'] = 'O reconhecimento acompanha o ritmo do roteiro.'
    plist['NSLocalNetworkUsageDescription'] = 'Conecta outro celular como controle remoto pela rede local.'
    plist.setdefault('NSAppTransportSecurity', {})['NSAllowsLocalNetworking'] = True
    with IOS_INFO.open('wb') as f:
        plistlib.dump(plist, f, sort_keys=False)

    podfile = ROOT / 'ios/Podfile'
    if podfile.is_file():
        value = podfile.read_text(encoding='utf-8')
        if re.search(r'^\s*platform :ios,', value, flags=re.M):
            value = re.sub(r'^\s*platform :ios,.*$', "platform :ios, '13.0'", value, count=1, flags=re.M)
        else:
            value = "platform :ios, '13.0'\n" + value
        podfile.write_text(value, encoding='utf-8')
    configurar_icone_ios()
    print('iOS: permissões e deployment target configurados (iOS 13+).')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=['auto', 'android', 'ios', 'both'], default='auto',
                        help='Padrão: configurar somente as pastas existentes')
    args = parser.parse_args()
    if args.platform == 'auto':
        platforms = set()
        if ANDROID_MANIFEST.is_file():
            platforms.add('android')
        if IOS_INFO.is_file():
            platforms.add('ios')
        if not platforms:
            raise SystemExit('Não existem pastas nativas. Execute: flutter create --platforms=android .')
    elif args.platform == 'both':
        platforms = {'android', 'ios'}
    else:
        platforms = {args.platform}

    if 'android' in platforms:
        configurar_android()
    if 'ios' in platforms:
        configurar_ios()
    print('NOTA: conexão LAN ws:// sem TLS; somente rede Wi-Fi de teste confiável.')


if __name__ == '__main__':
    main()
