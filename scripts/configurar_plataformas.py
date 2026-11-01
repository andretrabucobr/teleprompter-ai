#!/usr/bin/env python3
"""Configura as permissões nativas depois de `flutter create`.

Permite gerar Android no Windows/Linux sem exigir a pasta iOS (que só
precisa ser criada num Mac com Xcode). Idempotente.
"""
from pathlib import Path
import argparse
import plistlib
import re

ROOT = Path(__file__).resolve().parents[1]
ANDROID_MANIFEST = ROOT / 'android/app/src/main/AndroidManifest.xml'
IOS_INFO = ROOT / 'ios/Runner/Info.plist'


def configurar_android():
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
        query = ('<queries>\n        <intent>\n'
                 '            <action android:name="android.speech.RecognitionService" />\n'
                 '        </intent>\n    </queries>\n    ')
        content = content.replace('<application', query + '<application', 1)
    # Apenas para o WebSocket sem TLS em rede local durante o protótipo.
    if 'android:usesCleartextTraffic=' not in content:
        content = content.replace('<application',
                                  '<application android:usesCleartextTraffic="true"', 1)
    ANDROID_MANIFEST.write_text(content, encoding='utf-8')

    for gradle in (ROOT / 'android/app/build.gradle.kts',
                   ROOT / 'android/app/build.gradle'):
        if gradle.is_file():
            value = gradle.read_text(encoding='utf-8')
            value = value.replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')
            value = value.replace('minSdkVersion flutter.minSdkVersion', 'minSdkVersion 24')
            gradle.write_text(value, encoding='utf-8')
            break
    print('Android: permissões e SDK mínimo configurados (API 24).')


def configurar_ios():
    if not IOS_INFO.is_file():
        raise SystemExit('iOS não encontrado. No macOS, execute: flutter create --platforms=ios .')
    with IOS_INFO.open('rb') as f:
        plist = plistlib.load(f)
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
            value = re.sub(r'^\s*platform :ios,.*$', "platform :ios, '13.0'",
                           value, count=1, flags=re.M)
        else:
            value = "platform :ios, '13.0'\n" + value
        podfile.write_text(value, encoding='utf-8')
    print('iOS: permissões e deployment target configurados (iOS 13+).')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=['auto', 'android', 'ios', 'both'],
                        default='auto', help='Padrão: configurar somente as pastas existentes')
    args = parser.parse_args()
    platforms = set()
    if args.platform == 'auto':
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
