#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODEL="${1:-base}"
if [[ "$MODEL" != 'base' && "$MODEL" != 'tiny' ]]; then
  echo 'Uso: bash scripts/compilar_android_linux_macos.sh [base|tiny]' >&2; exit 2
fi
command -v flutter >/dev/null || { echo 'Flutter nao encontrado: https://docs.flutter.dev/get-started/install' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'Python 3.10+ nao encontrado' >&2; exit 1; }
if [[ ! -f android/app/src/main/AndroidManifest.xml ]]; then
  flutter create --platforms=android --project-name=teleprompter_ai .
fi
python3 scripts/configurar_plataformas.py --platform android
python3 scripts/configurar_splash.py --platform android
python3 scripts/instalar_modelo.py --model "$MODEL"
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --debug --target-platform android-arm64
mkdir -p dist
cp build/app/outputs/flutter-apk/app-debug.apk dist/OitoseteFlowText-v0.9.2-debug-Android-arm64.apk
echo "APK: $(pwd)/dist/OitoseteFlowText-v0.9.2-debug-Android-arm64.apk"
