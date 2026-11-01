#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != 'Darwin' ]]; then
  echo 'iOS so pode ser compilado em macOS com Xcode instalado.' >&2; exit 1
fi
MODEL="${1:-base}"
if [[ "$MODEL" != 'base' && "$MODEL" != 'tiny' ]]; then
  echo 'Uso: bash scripts/compilar_ios_macos.sh [base|tiny]' >&2; exit 2
fi
command -v flutter >/dev/null || { echo 'Instale Flutter SDK.' >&2; exit 1; }
command -v xcodebuild >/dev/null || { echo 'Instale Xcode.' >&2; exit 1; }
if [[ ! -f ios/Runner/Info.plist ]]; then
  flutter create --platforms=ios --project-name=teleprompter_ai .
fi
python3 scripts/configurar_plataformas.py --platform ios
python3 scripts/instalar_modelo.py --model "$MODEL"
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build ios --release --no-codesign
echo "iOS compilado sem assinatura: $(pwd)/build/ios/iphoneos/Runner.app"
echo 'Para instalar em iPhone fisico, assine o app usando Xcode e conta Apple.'
